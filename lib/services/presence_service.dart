import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Publishes whether the signed-in user is actually using the app right
/// now, to presence/{uid}, so the Messages list can show a truthful
/// "active" dot (see OnlineDot).
///
/// A user counts as online only while the app is open in the foreground
/// AND its heartbeat is still reaching the server. The heartbeat is the
/// part that covers lost internet, a crash or a force-close: none of those
/// can write "offline", but they all stop the heartbeat, and viewers treat
/// a heartbeat older than [staleAfter] as offline.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const Duration heartbeatEvery = Duration(seconds: 45);

  /// A little over two heartbeats, so one late beat doesn't flicker the
  /// dot off.
  static const Duration staleAfter = Duration(seconds: 100);

  bool _started = false;
  bool _foreground = true;
  Timer? _heartbeat;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('presence').doc(uid);
  }

  /// Call once, after Firebase is initialized.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Lives for the whole app session, like this service.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && _foreground) {
        _beginHeartbeat();
      } else {
        _heartbeat?.cancel();
      }
    });
  }

  void _beginHeartbeat() {
    _heartbeat?.cancel();
    _write(online: true);
    _heartbeat = Timer.periodic(heartbeatEvery, (_) => _write(online: true));
  }

  Future<void> _write({required bool online}) async {
    try {
      await _doc?.set({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best effort — a missed beat just lets the dot go stale.
    }
  }

  /// Call before FirebaseAuth.signOut() — afterwards this device is no
  /// longer allowed to write the account's presence doc.
  Future<void> goOffline() async {
    _heartbeat?.cancel();
    // Don't let a slow connection hold up signing out.
    await _write(
      online: false,
    ).timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      if (FirebaseAuth.instance.currentUser != null) _beginHeartbeat();
    } else {
      _heartbeat?.cancel();
      _write(online: false);
    }
  }

  /// Whether a presence/{uid} snapshot means "online right now".
  static bool isOnline(Map<String, dynamic>? presence) {
    if (presence == null || presence['online'] != true) return false;
    final lastSeen = presence['lastSeen'];
    if (lastSeen is! Timestamp) return false;
    return DateTime.now().difference(lastSeen.toDate()) < staleAfter;
  }
}
