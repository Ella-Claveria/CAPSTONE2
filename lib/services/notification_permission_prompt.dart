import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Why the app asks for notifications — said before the phone itself is
/// asked, wherever that happens.
const String kNotificationRationaleTitle = 'Stay Updated';
const String kNotificationRationaleMessage =
    'Allow notifications to receive important updates about your account, '
    'orders, messages, verification status, and other AgriTrade+ '
    'activities.';

/// Offers notification access once per device, the first time a user is
/// signed in with a verified email: on their own home screen
/// (FarmerHomeScreen / BuyerMarketplaceScreen), or — for a farmer who has
/// just registered — on the pending-approval screen, so the decision on
/// their application can reach this phone. Nothing before that (the
/// onboarding slides, login, registration, the email code screen, the
/// loading/auth checks) calls this.
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
        title: kNotificationRationaleTitle,
        message: kNotificationRationaleMessage,
        denyLabel: 'Not Now',
        allowLabel: 'Allow',
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



