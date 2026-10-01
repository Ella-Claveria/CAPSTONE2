import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../firebase_options.dart';
import '../services/connectivity_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/branded_loading_screen.dart';
import '../widgets/no_internet_screen.dart';
import 'app_router.dart';
import 'login_screen.dart';

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
    // ---- Step 1: is there even a network interface? ----
    // Cheap and Firebase-independent, so an obviously offline device (e.g.
    // airplane mode) never has to wait on anything else to find that out.
    setState(() => _phase = _BootPhase.checkingInternet);
    if (!await _hasNetworkInterface()) {
      if (!mounted) return;
      setState(() => _phase = _BootPhase.offline);
      return;
    }

    // ---- Step 2: local, network-independent Firebase SDK setup ----
    if (Firebase.apps.isEmpty) {
      setState(() => _phase = _BootPhase.initializing);
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } catch (e, st) {
        debugPrint('App startup failed: $e');
        debugPrintStack(stackTrace: st);
        if (mounted) setState(() { _error = e.toString(); _phase = _BootPhase.error; });
        return;
      }
    }

    // ---- Step 3: confirm Firebase is actually reachable, not just that ----
    // a network interface exists (a device can show full signal on a dead
    // access point or a captive portal and still have zero real access).
    setState(() => _phase = _BootPhase.checkingInternet);
    final reachable = await ConnectivityService.instance.checkNow(force: true);
    if (!mounted) return;
    if (!reachable) {
      setState(() => _phase = _BootPhase.offline);
      return;
    }

    // ---- Step 4: auth-adjacent setup (push notifications) ----
    setState(() => _phase = _BootPhase.checkingAuthentication);
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
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
      if (mounted) setState(() { _error = e.toString(); _phase = _BootPhase.error; });
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
    setState(() => _phase = _BootPhase.ready);
  }

  Future<bool> _hasNetworkInterface() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // Plugin unavailable on this platform/build — let the real Firebase
      // reachability probe in step 3 be the judge instead of blocking here.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _BootPhase.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('App failed to start.\n$_error', textAlign: TextAlign.center),
            ),
          ),
        );
      case _BootPhase.offline:
        return NoInternetScreen(
          message: kIsWeb ? kNoInternetAdminMessage : kNoInternetMessage,
          onRetry: _boot,
        );
      case _BootPhase.ready:
        // Flutter Web is the Admin portal only — same shared login design as
        // mobile, just pre-set to the admin door (see AuthRoutingService for
        // the actual role/platform enforcement after sign-in).
        return kIsWeb ? const LoginScreen(role: 'admin') : const AppRouter();
      case _BootPhase.initializing:
      case _BootPhase.checkingInternet:
      case _BootPhase.checkingAuthentication:
      case _BootPhase.loadingUser:
        return const BrandedLoadingScreen();
    }
  }
}
