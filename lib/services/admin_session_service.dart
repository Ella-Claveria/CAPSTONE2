import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_device_location.dart';
import 'auth_service.dart' show cleanFunctionMessage;

/// How this browser's Admin session stands against the one on record.
enum AdminSessionStanding {
  /// This browser holds the active session.
  current,

  /// Nothing stands in the way of this browser starting the session: no
  /// session is on record, the last one was logged out, or this browser
  /// no longer remembers a session id of its own.
  free,

  /// The account's active session is another browser's: this one was
  /// signed in elsewhere after it.
  endedHere,
}

/// Whether another browser is using the Admin account right now: its
/// session is the active one, was not logged out, and was heard from
/// within [AdminSessionService.staleAfter]. Pure, so it can be tested.
bool adminSessionActiveElsewhere(
  Map<String, dynamic>? record,
  String? localId, {
  required DateTime now,
}) {
  if (record == null) return false;
  final activeId = (record['activeSessionId'] ?? '').toString();
  if (activeId.isEmpty || activeId == localId) return false;
  if ((record['sessionStatus'] ?? 'active') != 'active') return false;
  final seen = record['lastActiveAt'];
  final lastActive = seen is Timestamp
      ? seen.toDate()
      : (seen is DateTime ? seen : null);
  // No time on record: treated as active — the safe reading.
  if (lastActive == null) return true;
  return now.difference(lastActive) <= AdminSessionService.staleAfter;
}

/// Where this browser stands when it comes back to the portal already
/// signed in (a refresh, a reopened browser). Pure, so it can be tested.
AdminSessionStanding adminSessionStanding(
  Map<String, dynamic>? record,
  String? localId, {
  required DateTime now,
}) {
  final activeId = (record?['activeSessionId'] ?? '').toString();
  if (record == null || activeId.isEmpty) return AdminSessionStanding.free;
  if (activeId == localId) {
    return (record['sessionStatus'] ?? 'active') == 'active'
        ? AdminSessionStanding.current
        : AdminSessionStanding.free;
  }
  // Another session id is the active one. A browser that remembers its
  // own id has been replaced. One that remembers none cannot tell: the
  // session on record may well be its own, with the id lost (the browser's
  // storage was cleared, or the session could not be saved). It is already
  // signed in, so it is not turned away — it takes the session over, as a
  // sign-in does (see AdminSessionGate).
  return localId != null
      ? AdminSessionStanding.endedHere
      : AdminSessionStanding.free;
}

/// One Admin session as Active Sessions lists it, from
/// `adminSessions/{uid}/history/{id}` (written by the adminSession Cloud
/// Function).
class AdminSessionEntry {
  final String id;

  /// "Chrome on Windows".
  final String device;
  final String platform;

  /// Approximate: the place the browser reported when it signed in.
  final String? location;
  final DateTime? startedAt;

  /// The last time it was heard from: the account's record for the active
  /// session (its heartbeat), else when it started.
  final DateTime? lastActiveAt;
  final DateTime? endedAt;

  /// Still signed in.
  final bool active;

  /// 'logout', 'replaced', 'superseded' or 'revoked' once ended.
  final String? endReason;

  /// This browser's own session.
  final bool isCurrent;

  const AdminSessionEntry({
    required this.id,
    required this.device,
    required this.platform,
    required this.location,
    required this.startedAt,
    required this.lastActiveAt,
    required this.endedAt,
    required this.active,
    required this.endReason,
    required this.isCurrent,
  });

  bool get onPhone {
    final p = platform.toLowerCase();
    return p.contains('android') || p.contains('ios');
  }

  /// How an ended session ended.
  String get endLabel => switch (endReason) {
    'logout' => 'Logged out',
    'revoked' => 'Signed out from Active Sessions',
    'replaced' || 'superseded' => 'Ended by a newer login',
    _ => 'Ended',
  };
}

DateTime? _dateOf(Object? value) => value is Timestamp
    ? value.toDate()
    : value is DateTime
    ? value
    : null;

/// The account's sessions, newest first, from its session [history] and
/// its session [record] (`adminSessions/{uid}`); [localId] is this
/// browser's own session. Pure, so it can be tested.
List<AdminSessionEntry> buildAdminSessionEntries({
  required Map<String, dynamic>? record,
  required List<({String id, Map<String, dynamic> data})> history,
  required String? localId,
}) {
  final activeId = (record?['activeSessionId'] ?? '').toString();
  final entries = [
    for (final doc in history)
      AdminSessionEntry(
        id: doc.id,
        device: (doc.data['deviceName'] ?? '').toString().trim().isEmpty
            ? 'Unknown device'
            : doc.data['deviceName'].toString(),
        platform: (doc.data['platform'] ?? '').toString(),
        location: () {
          final place = (doc.data['location'] ?? '').toString().trim();
          return place.isEmpty || place == 'Unknown' ? null : place;
        }(),
        startedAt: _dateOf(doc.data['startedAt']),
        lastActiveAt: doc.id == activeId
            ? _dateOf(record?['lastActiveAt']) ??
                  _dateOf(doc.data['lastActiveAt'])
            : _dateOf(doc.data['lastActiveAt']) ??
                  _dateOf(doc.data['startedAt']),
        endedAt: _dateOf(doc.data['endedAt']),
        active: (doc.data['status'] ?? 'active') == 'active',
        endReason: doc.data['endReason']?.toString(),
        isCurrent: localId != null && doc.id == localId,
      ),
  ];
  entries.sort(
    (a, b) => (b.startedAt?.millisecondsSinceEpoch ?? 0).compareTo(
      a.startedAt?.millisecondsSinceEpoch ?? 0,
    ),
  );
  return entries;
}

/// The Admin Portal's single active session: one browser at a time per
/// Admin account.
///
/// Firebase Authentication still signs the Admin in. This only keeps track
/// of WHICH browser session is the active one — `adminSessions/{uid}` —
/// so that signing in on a second browser ends the first. The record is
/// written by the `adminSession` Cloud Function (functions/admin_session.js),
/// which also emails the sign-in alert and writes the Audit Log; this
/// browser only remembers its own session id, and reads the record.
///
/// If the record cannot be reached or the function is unavailable, the
/// Admin is let in without the check rather than locked out: the account
/// is still protected by its password and by Firestore rules.
class AdminSessionService {
  AdminSessionService._();

  /// A session not heard from for this long is no longer "in use": the
  /// next sign-in takes over without asking.
  static const Duration staleAfter = Duration(minutes: 15);

  /// How often an open portal says its session is still in use.
  static const Duration heartbeat = Duration(minutes: 5);

  static final _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  static DocumentReference<Map<String, dynamic>> _record(String uid) =>
      FirebaseFirestore.instance.collection('adminSessions').doc(uid);

  static String _localKey(String uid) => 'admin_session_id_$uid';

  /// This browser's session id for [uid], or null if it holds none.
  static Future<String?> localId(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_localKey(uid));
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLocal(String uid, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey(uid), id);
  }

  /// Forgets this browser's session id.
  static Future<void> clearLocal(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localKey(uid));
    } catch (_) {}
  }

  // Random, and nothing else: 24 bytes from the secure generator.
  static String _newId() {
    final random = Random.secure();
    return base64UrlEncode([
      for (var i = 0; i < 24; i++) random.nextInt(256),
    ]).replaceAll('=', '');
  }

  /// The session on record, read from the server (never a cached copy).
  /// Null when there is none. Throws when it cannot be read.
  static Future<Map<String, dynamic>?> readRecord(String uid) async {
    final snap = await _record(
      uid,
    ).get(const GetOptions(source: Source.server));
    return snap.data();
  }

  /// Makes this browser the active session. With [silent], no sign-in
  /// alert is sent and nothing is written to the Audit Log — for a
  /// session picked up again, which is not a new sign-in.
  ///
  /// False when it could not be done; the browser then holds no session
  /// id, so it is not checked against the record (see the class doc).
  static Future<bool> start(String uid, {bool silent = false}) async {
    try {
      // The same id when this browser already holds the active session;
      // otherwise a new one.
      var id = await localId(uid);
      Map<String, dynamic>? record;
      try {
        record = await readRecord(uid);
      } catch (_) {}
      if (id == null || (record?['activeSessionId'] ?? id) != id) {
        id = _newId();
      }
      await _functions
          .httpsCallable('adminSession')
          .call({
            'op': 'start',
            'sessionId': id,
            'silent': silent,
            // For the Audit Log entries a sign-in writes. Signing in is
            // not kept waiting for it.
            'location': ?await AdminDeviceLocation.current(
              wait: const Duration(seconds: 2),
            ),
          })
          .timeout(const Duration(seconds: 20));
      await _saveLocal(uid, id);
      return true;
    } catch (error) {
      debugPrint('[AdminSession] could not start the session: $error');
      await clearLocal(uid);
      return false;
    }
  }

  /// Logout: ends this browser's session, if it is still the active one.
  /// Must be called while still signed in.
  static Future<void> end(String uid) async {
    final id = await localId(uid);
    await clearLocal(uid);
    if (id == null) return;
    try {
      await _functions
          .httpsCallable('adminSession')
          .call({'op': 'end', 'sessionId': id})
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Left on record as active; it goes quiet and is taken over by the
      // next sign-in without asking.
    }
  }

  /// Says this browser's session is still in use.
  static Future<void> touch(String uid) async {
    try {
      final id = await localId(uid);
      if (id == null) return;
      await _record(uid).update({'lastActiveAt': FieldValue.serverTimestamp()});
    } catch (_) {
      // Missed once: the next one says it.
    }
  }

  /// Emits once this browser's session is no longer the active one — the
  /// account signed in on another browser. Only the server's word counts,
  /// and a browser holding no session id is never told so.
  static Stream<void> watchEnded(String uid) async* {
    await for (final snap in _record(uid).snapshots()) {
      if (snap.metadata.isFromCache || !snap.exists) continue;
      final id = await localId(uid);
      if (id == null) continue;
      final activeId = (snap.data()?['activeSessionId'] ?? '').toString();
      if (activeId.isNotEmpty && activeId != id) {
        yield null;
        return;
      }
    }
  }

  /// This account's recent sessions, newest first — the bell's "new
  /// sign-in" notices, and Active Sessions ([limit] of them).
  static Stream<QuerySnapshot<Map<String, dynamic>>> recentSessions(
    String uid, {
    int limit = 10,
  }) => _record(uid)
      .collection('history')
      .orderBy('startedAt', descending: true)
      .limit(limit)
      .snapshots();

  /// The account's session record, live.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRecord(
    String uid,
  ) => _record(uid).snapshots();

  /// Active Sessions > Revoke Session: signs out the session [sessionId] —
  /// or, when it is null, every session but this browser's. Null when it
  /// was done, or a message to show.
  ///
  /// Firebase Authentication cannot sign out a single device, so the
  /// revokeAdminSession Cloud Function revokes the account's sign-ins and
  /// refuses every token older than this password entry (see
  /// functions/admin_session.js). Every other signed-in device is signed
  /// out with it. This browser then signs in again with the same password,
  /// so it keeps working.
  static Future<String?> revoke({
    required String password,
    String? sessionId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) return 'Please log in again.';
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    // 1. It is you: the server only revokes within minutes of this.
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'wrong-password' ||
        'invalid-credential' ||
        'invalid-login-credentials' => 'Incorrect password.',
        'too-many-requests' =>
          'Too many attempts. Please wait a bit and try again.',
        'network-request-failed' =>
          'No internet connection. Please check your connection and try again.',
        _ => 'Your password could not be checked. Please try again.',
      };
    }

    // 2. The server signs the session out.
    try {
      await _functions
          .httpsCallable('revokeAdminSession')
          .call({
            'sessionId': sessionId,
            'currentSessionId': await localId(user.uid),
            // For the Audit Log entry.
            'location': ?await AdminDeviceLocation.current(
              wait: const Duration(seconds: 2),
            ),
          })
          .timeout(const Duration(seconds: 30));
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[AdminSession] revoke failed: ${e.code} ${e.message}');
      final own = cleanFunctionMessage(e.message) ?? '';
      return switch (e.code) {
        'failed-precondition' ||
        'not-found' ||
        'permission-denied' when own.isNotEmpty => own,
        'unauthenticated' => 'Your session has expired. Please log in again.',
        'unavailable' ||
        'deadline-exceeded' => 'Check your internet connection and try again.',
        _ => 'The session could not be signed out. Please try again.',
      };
    } catch (e) {
      debugPrint('[AdminSession] revoke failed: $e');
      return 'The session could not be signed out. Please try again.';
    }

    // 3. This browser's own sign-in was revoked with the others: renew it,
    //    so it does not end when its token next expires.
    try {
      await user.reauthenticateWithCredential(credential);
    } catch (e) {
      debugPrint('[AdminSession] could not renew this sign-in: $e');
    }
    return null;
  }
}
