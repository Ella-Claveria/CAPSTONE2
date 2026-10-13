import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/commodity_master_list.dart';
import '../firebase_options.dart';
import '../services/connectivity_service.dart';
import '../services/device_trust_service.dart';
import '../services/presence_service.dart';
import '../services/product_share_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/branded_loading_screen.dart';
import '../widgets/no_internet_screen.dart';
import 'app_router.dart';
import 'admin_session_gate.dart';

// One listener for the whole app run — AppBootstrap itself can be rebuilt
// (e.g. after a session timeout).
StreamSubscription<User?>? _authLogSub;

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate; keep it minimal.
  debugPrint("Handling a background message: ${message.messageId}");
}

/// The states this splash gate moves through, in order, on a normal run.
/// AgriTrade+ depends on live Firebase data (approval status, inventory,
/// orders, admin stats), so nothing past [offline] is ever reachable
/// without a confirmed connection — Login, Farmer/Buyer Home, and the
/// Admin Dashboard must never flash on screen before that's verified.
enum _BootPhase {
  initializing,
  checkingInternet,
  offline,
  checkingAuthentication,
  loadingUser,
  ready,
  error,
}

/// Shown as the app's `home` so the branded loading screen is the very
/// first frame Flutter draws — no waiting on Firebase before the user sees
/// anything moving. Everything past that (connectivity, Firebase init,
/// auth/role routing) runs behind that spinner or the offline screen below,
/// never behind a screen that looks like the real app.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  _BootPhase _phase = _BootPhase.initializing;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // ---- Step 1: nothing is decided from the network interface alone ----
    // connectivity_plus can report "none" on a device that is in fact
    // online, so it never blocks startup by itself; step 3's real
    // reachability check is the only judge.

    // ---- Step 2: local, network-independent Firebase SDK setup ----
    if (Firebase.apps.isEmpty) {
      setState(() => _phase = _BootPhase.initializing);
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e, st) {
        debugPrint('App startup failed: $e');
        debugPrintStack(stackTrace: st);
        if (mounted) {
          setState(() {
            _error = e.toString();
            _phase = _BootPhase.error;
          });
        }
        return;
      }
    }

    // Debug trail for unexpected logouts: every sign-in / sign-out /
    // restored session is printed with its uid and email. Pair it with the
    // "[Auth] signOut() called — reason: …" line from AuthService.signOut
    // to see exactly what ended a session.
    _authLogSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint(
        user == null
            ? '[Auth] auth state changed → signed OUT (no current user)'
            : '[Auth] auth state changed → signed IN '
                  '(uid: ${user.uid}, email: ${user.email})',
      );
    });

    // ---- Step 3: confirm Firebase is actually reachable, not just that ----
    // a network interface exists (a device can show full signal on a dead
    // access point or a captive portal and still have zero real access).
    setState(() => _phase = _BootPhase.checkingInternet);
    final reachable = await ConnectivityService.instance.checkNow(
      force: true,
      reason: 'app start',
    );
    if (!mounted) return;
    if (!reachable) {
      setState(() => _phase = _BootPhase.offline);
      return;
    }

    // ---- Step 4: auth-adjacent setup (push notifications) ----
    setState(() => _phase = _BootPhase.checkingAuthentication);
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
      }
      // Notification permission itself is never requested here — this phase
      // runs on every single boot (every page load, before anyone is even
      // logged in on web), so asking here would re-prompt constantly. Mobile
      // asks after a successful mobile login (see LoginFormFields). The
      // admin web portal does not use this mobile push-permission flow.
      // Registers onMessage (foreground display), onMessageOpenedApp
      // (background tap), and captures getInitialMessage() (terminated-app
      // tap) — see PushNotificationService for why the terminated case is
      // deferred rather than acted on immediately at this point.
      await PushNotificationService().initMessageHandling();
    } catch (e, st) {
      debugPrint('App startup failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _phase = _BootPhase.error;
        });
      }
      return;
    }

    // ---- Step 5: hand off ----
    // The actual "who is this / what's their role" lookup happens in
    // AppRouter (mobile) and LoginScreen -> AuthRoutingService (both
    // platforms) — this gate's job stops at "it's safe to let them try".
    if (!mounted) return;
    setState(() => _phase = _BootPhase.loadingUser);
    // Now that we're past the gate, watch for connectivity being lost again
    // while the user is inside the app (a single, shared watchdog — see
    // ConnectivityService — not a new timer/poll loop).
    ConnectivityService.instance.startWatching();
    // Publishes this user's "active now" status while the app is open
    // (the green dot in Messages — see PresenceService).
    PresenceService.instance.start();
    // Follows the Admin-managed commodity list (Supported Products, Add
    // Product suggestions, units) — see CommodityRegistry.
    CommodityRegistry.instance.start();
    // Opens Product Details for a shared product link (see
    // ProductLinkService) once the user is signed in and Home is up.
    ProductLinkService.start();
    // Recognizes this installation for the signed-in account (New Device
    // Login Alert) — see DeviceTrustService.
    DeviceTrustService.instance.start();
    setState(() => _phase = _BootPhase.ready);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _BootPhase.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'App failed to start.\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      case _BootPhase.offline:
        return NoInternetScreen(
          message: kIsWeb ? kNoInternetAdminMessage : kNoInternetMessage,
          onRetry: _boot,
        );
      case _BootPhase.ready:
        // Flutter Web is the Admin portal only. AdminSessionGate restores an
        // existing Admin session (e.g. after a page refresh) or shows the
        // admin login door (see AuthRoutingService for the actual
        // role/platform enforcement).
        return kIsWeb ? const AdminSessionGate() : const AppRouter();
      case _BootPhase.initializing:
      case _BootPhase.checkingInternet:
      case _BootPhase.checkingAuthentication:
      case _BootPhase.loadingUser:
        return const BrandedLoadingScreen();
    }
  }
}
