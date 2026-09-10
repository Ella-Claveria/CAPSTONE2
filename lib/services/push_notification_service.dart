import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_navigation_service.dart';

/// FCM is device push delivery only — Firestore (notifications/{uid}/items,
/// written by functions/index.js) remains the actual notification history
/// and unread/read state. This service's job is purely: keep this device's
/// token current, and make sure a tap on a notification — however the OS
/// delivered it (foreground banner, background tray tap, cold-start tap) —
/// opens the same destination via NotificationNavigationService.
class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _messageHandlingReady = false;

  static const AndroidNotificationChannel _transactionsChannel = AndroidNotificationChannel(
    'agritrade_transactions',
    'AgriTrade+ Transactions',
    description: 'Order, verification, and message updates',
    importance: Importance.high,
  );

  // Set by getInitialMessage() at cold start, before the app has finished
  // routing to Home — consumePendingNavigation() replays it once Home has
  // actually mounted, so a terminated-app notification tap can never race
  // (and skip past) auth/role routing.
  static RemoteMessage? _pendingInitialMessage;
  static bool _initialMessageChecked = false;

  Future<void> setupFCM() async {
    try {
      // On web this can fail if messaging is unavailable (service worker/
      // permission/browser mode). Do not block app startup for this.
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await _fcm.getToken();
        if (token != null) {
          await _saveTokenToFirestore(token);
        }
        _fcm.onTokenRefresh.listen(_saveTokenToFirestore);
      }
      // Denied/notDetermined: fall through without blocking anything — the
      // in-app Notifications screen still works off Firestore either way.
    } catch (e) {
      if (kDebugMode) {
        // Keep this non-fatal; messaging must not crash the app.
        // ignore: avoid_print
        print('FCM setup skipped: $e');
      }
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    await _db.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastTokenUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Registers the foreground/background/terminated message handlers.
  /// Safe to call once at startup regardless of platform or auth state —
  /// it only listens; it never requests permission or a token itself.
  Future<void> initMessageHandling() async {
    if (_messageHandlingReady) return;
    _messageHandlingReady = true;

    if (!kIsWeb) {
      await _initLocalNotifications();
    }

    // Foreground: FCM delivers the RemoteMessage but the OS does not show a
    // tray notification by itself, so this shows one via
    // flutter_local_notifications (Part 8 of the notification spec).
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background: app was running, user tapped the system tray notification.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationNavigationService.open(
        type: (message.data['type'] ?? '').toString(),
        data: message.data,
      );
    });

    // Terminated: app was launched by tapping the system tray notification.
    // Stored rather than acted on immediately — see consumePendingNavigation.
    if (!_initialMessageChecked) {
      _initialMessageChecked = true;
      try {
        _pendingInitialMessage = await _fcm.getInitialMessage();
      } catch (_) {
        // Non-fatal — worst case a cold-start tap just opens straight to Home.
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload) as Map<String, dynamic>;
          NotificationNavigationService.open(
            type: (decoded['type'] ?? '').toString(),
            data: Map<String, dynamic>.from(decoded['data'] ?? {}),
          );
        } catch (_) {}
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_transactionsChannel);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Got a foreground message: ${message.data}');
    final notification = message.notification;
    if (notification == null || kIsWeb) return;

    // A stable-but-unique id per message (rather than a fixed constant)
    // means several notifications arriving in a row each get their own
    // tray entry instead of silently overwriting one another — while a
    // genuine retry of the exact same message never posts a second one.
    final id = message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch;

    _localNotifications.show(
      id: id,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _transactionsChannel.id,
          _transactionsChannel.name,
          channelDescription: _transactionsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'type': message.data['type'], 'data': message.data}),
    );
  }

  /// Call once Farmer/Buyer Home has actually mounted (i.e. auth + role
  /// routing has already finished) so a cold-start notification tap opens
  /// its destination without ever racing that routing.
  static Future<void> consumePendingNavigation() async {
    final message = _pendingInitialMessage;
    if (message == null) return;
    _pendingInitialMessage = null;
    await Future.delayed(const Duration(milliseconds: 300));
    await NotificationNavigationService.open(
      type: (message.data['type'] ?? '').toString(),
      data: message.data,
    );
  }
}
