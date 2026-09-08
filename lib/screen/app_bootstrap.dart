import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';
import '../services/push_notification_service.dart';
import '../widgets/branded_loading_screen.dart';
import 'admin_login_screen.dart';
import 'app_router.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate; keep it minimal.
  debugPrint("Handling a background message: ${message.messageId}");
}

/// Shown as the app's `home` so the branded loading screen is the very
/// first frame Flutter draws — no waiting on Firebase before the user sees
/// anything moving. Firebase init (and everything that depends on it) runs
/// in the background behind that spinner instead of blocking runApp().
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Background handlers are not used on web the same way as mobile.
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      }

      // Mobile asks for notification permission itself, from the onboarding
      // / app-router flow, so it can be requested alongside location and
      // after the user has seen what the app is for. Web (the admin portal)
      // skips that flow entirely, so it sets up FCM eagerly here instead.
      if (kIsWeb) {
        await PushNotificationService().setupFCM();
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a foreground message: ${message.data}');
        if (message.notification != null) {
          debugPrint('Message also contained a notification: ${message.notification?.title}');
        }
      });
    } catch (e, st) {
      debugPrint('App startup failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) setState(() => _error = e.toString());
      return;
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('App failed to start.\n$_error', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_ready) {
      return kIsWeb ? AdminLoginScreen() : const AppRouter();
    }
    return const BrandedLoadingScreen();
  }
}
