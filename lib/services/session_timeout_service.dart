import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screen/app_bootstrap.dart';
import 'auth_service.dart';

/// Signs the signed-in user out after the app has sat backgrounded and
/// untouched for [kIdleTimeout] — NOT on every relaunch. Firebase Auth's
/// own session already persists across a normal close/reopen, and
/// AppRouter/AuthRoutingService already route a still-valid session
/// straight to its home screen on cold start; this only adds the missing
/// piece, an actual idle timeout, on top of that.
///
/// The backgrounded-at timestamp is kept in SharedPreferences (not just
/// memory) because Android can kill the process outright while it sits in
/// the background for that long — especially under aggressive OEM battery
/// management — so the idle clock has to survive a full process kill and
/// still be honored on the next cold start (see [signOutIfIdleTooLong],
/// called from AppRouter for exactly that case).
class SessionTimeoutService extends WidgetsBindingObserver {
  SessionTimeoutService._();
  static final SessionTimeoutService instance = SessionTimeoutService._();

  static const _backgroundedAtKey = 'session_backgrounded_at_ms';
  static const kIdleTimeout = Duration(minutes: 15);

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _idleTimer;

  /// Call once from main(), before runApp — [navigatorKey] is used to force
  /// the app back to the login flow if the timeout fires while the app is
  /// still alive in memory (backgrounded, not killed) and gets resumed.
  void start(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Starts or refreshes the active-session inactivity clock. Lifecycle
  /// timestamps separately cover a suspended app and process restarts.
  void recordActivity() {
    if (FirebaseAuth.instance.currentUser == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(kIdleTimeout, _expireActiveSession);
  }

  Future<void> _expireActiveSession() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await AuthService().signOut();
    final navState = _navigatorKey?.currentState;
    if (navState == null) return;
    navState.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppBootstrap()),
      (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_markBackgrounded());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAndMaybeSignOut());
    }
  }

  Future<void> _markBackgrounded() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_backgroundedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Non-fatal — worst case this one background period isn't timed.
    }
  }

  Future<void> _resumeAndMaybeSignOut() async {
    final timedOut = await signOutIfIdleTooLong();
    if (!timedOut) {
      recordActivity();
      return;
    }
    // The process survived the background period, so whatever screen was
    // on screen (Farmer/Buyer Home, a product page, etc.) is still on the
    // Navigator stack — this is the one path that needs to force its own
    // navigation back to login; the cold-start path below doesn't, since
    // AppRouter's own "not signed in" branch already handles it.
    final navState = _navigatorKey?.currentState;
    if (navState == null) return;
    navState.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppBootstrap()),
      (route) => false,
    );
  }

  /// Signs the user out if the app was backgrounded at least
  /// [kIdleTimeout] ago — including across a process kill, so AppRouter
  /// calls this before its own "already signed in" check on every cold
  /// start. Safe to call any time; a no-op when nobody's logged in or the
  /// background period (if any) wasn't long enough. Returns whether it
  /// signed the user out.
  Future<bool> signOutIfIdleTooLong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_backgroundedAtKey);
      await prefs.remove(_backgroundedAtKey);
      if (ms == null) return false;
      if (FirebaseAuth.instance.currentUser == null) return false;

      final backgroundedAt = DateTime.fromMillisecondsSinceEpoch(ms);
      if (DateTime.now().difference(backgroundedAt) < kIdleTimeout) return false;

      await AuthService().signOut();
      return true;
    } catch (_) {
      return false;
    }
  }
}
