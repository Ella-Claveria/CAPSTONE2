import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Offers notification access once, immediately after an existing user logs
/// in on this device. Registration and email verification never call this.
class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();
  static final instance = NotificationPermissionPrompt._();

  static const _askedKey = 'asked_notification_permission';

  bool _handling = false;

  Future<void> afterLogin(BuildContext context) async {
    if (_handling) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Wait until the account is actually verified (email verification for
    // password sign-up, automatic for Google) — otherwise this could fire
    // while the user is still stuck on EmailVerificationScreen, before
    // they've "successfully logged in" in the sense item 16 means.
    if (!user.emailVerified) return;

    _handling = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final asked = prefs.getBool(_askedKey) ?? false;
      if (asked) return;

      // Already granted (e.g. re-installed after previously allowing) —
      // nothing to explain, and asking again would be unnecessary.
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await prefs.setBool(_askedKey, true);
        try {
          await PushNotificationService().setupFCM();
        } catch (_) {}
        return;
      }

      await prefs.setBool(_askedKey, true);

      if (!context.mounted) return;
      final proceed = await showPermissionRationale(
        context,
        icon: Icons.notifications_active_outlined,
        title: 'Stay Updated with AgriTrade+',
        message: 'Payagan ang notifications para makatanggap ka ng updates tungkol sa orders, messages, verification status, delivery o pick-up, warnings, at ibang importanteng marketplace activities.',
        denyLabel: 'Not Now',
        allowLabel: 'Enable Notifications',
      );
      if (proceed) {
        try {
          await PushNotificationService().setupFCM(requestPermission: true);
        } catch (_) {}
      }
    } catch (_) {
      // Can't read/persist the flag right now — just skip this tap and try
      // again on the next one.
    } finally {
      _handling = false;
    }
  }
}



