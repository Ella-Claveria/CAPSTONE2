import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_device_location.dart';
import '../services/admin_session_service.dart';
import '../services/auth_routing_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/branded_loading_screen.dart';
import '../widgets/no_internet_screen.dart';
import 'auth_route_handler.dart';
import 'login_screen.dart';

/// The web Admin Portal's front door: restores an existing Admin session
/// (page refresh, reopened tab) instead of always showing the login page.
///
/// Stays on the loading screen until BOTH Firebase Auth has finished
/// restoring its saved session and the account's Firestore role has been
/// read — nothing is decided, and nobody is signed out, while either is
/// still loading. A role read that fails is offered as a retry; only a
/// confirmed result (no user, restricted account, role is not admin) ends
/// at the login page, via the shared [applyAuthRouteResult].
class AdminSessionGate extends StatefulWidget {
  const AdminSessionGate({super.key});

  @override
  State<AdminSessionGate> createState() => _AdminSessionGateState();
}

enum _GateState { checking, signedOut, roleCheckFailed }

class _AdminSessionGateState extends State<AdminSessionGate> {
  _GateState _state = _GateState.checking;

  // Back at login because the account signed in on another device.
  bool _sessionEnded = false;

  @override
  void initState() {
    super.initState();
    // For the Audit Log's Location: found now, so it is known by the time
    // the Admin logs in.
    AdminDeviceLocation.warmUp();
    _restore();
  }

  Future<void> _restore() async {
    if (_state != _GateState.checking) {
      setState(() => _state = _GateState.checking);
    }

    // currentUser is null for a moment on a fresh page load, until Firebase
    // has read the saved session back from the browser — the first
    // authStateChanges event is the real answer.
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;
    debugPrint(
      '[AdminGate] session restore — uid: ${user?.uid}, email: ${user?.email}',
    );
    if (user == null) {
      setState(() => _state = _GateState.signedOut);
      return;
    }

    // The saved session is only what this browser remembers. Ask Firebase
    // whether it still stands: an account that was disabled or deleted, or
    // whose sessions were revoked (e.g. by a password change elsewhere),
    // goes back to login. Anything else that goes wrong here is a
    // connection problem — the role read below then fails and offers a
    // retry, and nobody is signed out for it.
    try {
      await user.reload();
    } on FirebaseAuthException catch (e) {
      const invalidSession = {
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      };
      if (invalidSession.contains(e.code)) {
        debugPrint(
          '[AdminGate] saved session is no longer valid (${e.code}) — '
          'signing out',
        );
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        if (!mounted) return;
        setState(() => _state = _GateState.signedOut);
        return;
      }
    } catch (_) {}
    if (!mounted) return;

    debugPrint('[AdminGate] checking Firestore role for uid: ${user.uid}…');
    final result = await AuthRoutingService.decide(user.uid);
    if (!mounted) return;

    if (result.decision == AuthRouteDecision.error) {
      // Could not read the role — unknown, not unauthorized. Keep the
      // session and let the admin retry.
      debugPrint(
        '[AdminGate] role check failed — keeping session, no sign-out',
      );
      setState(() => _state = _GateState.roleCheckFailed);
      return;
    }
    // An Admin is let back in only while this browser's session is still
    // the account's active one: signing in on another device ends it here.
    if (result.decision == AuthRouteDecision.adminDashboard &&
        !await _sessionStillHere(user.uid)) {
      debugPrint(
        '[AdminGate] this browser is not the active Admin session — '
        'signing out',
      );
      await AdminSessionService.clearLocal(user.uid);
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sessionEnded = true;
        _state = _GateState.signedOut;
      });
      return;
    }
    if (!mounted) return;
    // adminDashboard → the dashboard; anything else is a confirmed block
    // (signs out with the reason logged, explains, returns to login).
    await applyAuthRouteResult(context, result);
  }

  // True when this browser may carry on as the Admin's session. A session
  // record that cannot be read is not a reason to sign anyone out.
  Future<bool> _sessionStillHere(String uid) async {
    final Map<String, dynamic>? record;
    try {
      record = await AdminSessionService.readRecord(uid);
    } catch (_) {
      return true;
    }
    final standing = adminSessionStanding(
      record,
      await AdminSessionService.localId(uid),
      now: DateTime.now(),
    );
    switch (standing) {
      case AdminSessionStanding.current:
        return true;
      case AdminSessionStanding.endedHere:
        return false;
      case AdminSessionStanding.free:
        // Already signed in, with no session of its own on record: this
        // browser becomes the session. Quietly when nothing is in use;
        // when a session is in use (which may be this browser's own, its
        // id lost), it is taken over as a sign-in is — alert and Audit
        // Log included.
        await AdminSessionService.start(
          uid,
          silent: !adminSessionActiveElsewhere(
            record,
            null,
            now: DateTime.now(),
          ),
        );
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.checking:
        return const BrandedLoadingScreen();
      case _GateState.signedOut:
        return LoginScreen(role: 'admin', adminSessionEnded: _sessionEnded);
      case _GateState.roleCheckFailed:
        return NoInternetScreen(
          message: kNoInternetAdminMessage,
          onRetry: _restore,
        );
    }
  }
}
