import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_device_location.dart';

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
  /// sign-in" notices.
  static Stream<QuerySnapshot<Map<String, dynamic>>> recentSessions(
    String uid,
  ) => _record(uid)
      .collection('history')
      .orderBy('startedAt', descending: true)
      .limit(10)
      .snapshots();
}
