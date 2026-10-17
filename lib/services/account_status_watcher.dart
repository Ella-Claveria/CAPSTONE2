import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart';

import '../screen/auth_route_handler.dart';
import 'auth_routing_service.dart';

/// Ends a buyer's or farmer's session the moment an Admin suspends or bans
/// the account, while the app is open: signed out, back at the login
/// screen, with the "Account Suspended" notice and its reason and end
/// time (see AuthRoutingService.decideFromData).
///
/// A login, and every cold start, already check the account
/// (AppRouter, LoginFormFields), so this only acts on a CHANGE seen while
/// the session is open — never on the first reading — and the notice is
/// not shown twice. The web Admin Portal has its own watcher
/// (AdminDashboardScreen).
class AccountStatusWatcher {
  AccountStatusWatcher._();
  static final AccountStatusWatcher instance = AccountStatusWatcher._();

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<User?>? _auth;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _account;
  bool _handling = false;

  /// Call once from main(), before runApp.
  void start(GlobalKey<NavigatorState> navigatorKey) {
    if (kIsWeb || _auth != null) return;
    _navigatorKey = navigatorKey;
    // authStateChanges needs Firebase, which AppBootstrap initialises
    // after the first frame: wait for it there.
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenWhenReady());
  }

  Future<void> _listenWhenReady() async {
    for (var i = 0; i < 60; i++) {
      try {
        _auth = FirebaseAuth.instance.authStateChanges().listen(_watch);
        return;
      } catch (_) {
        // Firebase is not initialised yet.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _watch(User? user) {
    _account?.cancel();
    _account = null;
    if (user == null) return;
    var restrictedBefore = true;
    var first = true;
    _account = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
          if (snap.metadata.isFromCache) return;
          final result = AuthRoutingService.decideFromData(snap.data());
          final restricted =
              result.decision == AuthRouteDecision.accountRestricted;
          if (!first && restricted && !restrictedBefore) {
            unawaited(_endSession(result));
          }
          first = false;
          restrictedBefore = restricted;
        }, onError: (_) {});
  }

  Future<void> _endSession(AuthRouteResult result) async {
    if (_handling) return;
    final context = _navigatorKey?.currentState?.overlay?.context;
    if (context == null) return;
    _handling = true;
    debugPrint('[Account] suspended or banned while signed in: signing out');
    try {
      await applyAuthRouteResult(context, result);
    } finally {
      _handling = false;
    }
  }
}
