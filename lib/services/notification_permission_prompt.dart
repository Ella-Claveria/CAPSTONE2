import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Offers notification access once per device, the first time a user reaches
/// their own home screen (FarmerHomeScreen / BuyerMarketplaceScreen) — so
/// only after login, email verification and, for farmers, admin approval.
/// Nothing on the way there (login, registration, the email code screen,
/// the loading/auth checks, the pending-approval screen) calls this.
///
/// "Not Now" closes it without asking the OS for anything; the Notifications
/// screen offers the same choice again whenever the user wants it.
class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();
  static final instance = NotificationPermissionPrompt._();

  static const _askedKey = 'asked_notification_permission';

  bool _handling = false;

  Future<void> onEnteredApp(BuildContext context) async {
    if (_handling) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // The home screens are only reachable once verified; this is a second
    // guard, not the thing that decides the timing.
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
        message:
            'Allow notifications to receive important updates about orders, messages, verification status, delivery or pickup, warnings, and other marketplace activities.',
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



