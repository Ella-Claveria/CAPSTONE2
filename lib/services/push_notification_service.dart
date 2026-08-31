import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
}