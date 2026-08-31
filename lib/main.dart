import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screen/splash_screen.dart';
import 'screen/admin_login_screen.dart'; // Added the admin login screen import
import 'services/push_notification_service.dart'; 

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate; keep it minimal.
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  // Tells Flutter to get itself ready before we run any setup
  // code. Without this line, Firebase.initializeApp() crashes.
  WidgetsFlutterBinding.ensureInitialized();

  // Connects your app to your Firebase project (agritrade-bef87).
  // If this is missing, you get the error:
  //   "No Firebase App '[DEFAULT]' has been created"
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Background handlers are not used on web the same way as mobile.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    final pushService = PushNotificationService();
    await pushService.setupFCM();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a foreground message: ${message.data}');
      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification?.title}');
      }
    });

    runApp(const AgriTradeApp());
  } catch (e, st) {
    debugPrint('App startup failed: $e');
    debugPrintStack(stackTrace: st);
    runApp(StartupErrorApp(error: e.toString()));
  }
}

class AgriTradeApp extends StatelessWidget {
  const AgriTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriTrade+',

      // Hides the red "DEBUG" ribbon in the corner.
      debugShowCheckedModeBanner: false,

      // One line = Montserrat everywhere, plus your green theme.
      theme: AppTheme.themeData(),

      // Checks if running on the web. If true, show Admin Portal. If false, show Splash Screen.
      home: kIsWeb ? AdminLoginScreen() : const SplashScreen(),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  final String error;

  const StartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'App failed to start.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}