import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Watches for the very first tap a logged-in user makes anywhere in the
/// app and, if this device has never been asked before, that tap is the
/// moment we explain and request notification access — rather than
/// surprising a brand-new user with a system dialog before they've done
/// anything, or waiting until they happen to open the Notifications screen.
/// Covers both a newly-verified user's first login and an existing user's
/// first tap on a fresh install (the SharedPreferences flag is per-device,
/// so a reinstall naturally resets it).
class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();
  static final instance = NotificationPermissionPrompt._();

  static const _askedKey = 'asked_notification_permission';

  bool _handling = false;

  Future<void> maybeHandleFirstTap(BuildContext? context) async {
    if (_handling || context == null) return;
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
        message: "Enable notifications so you won't miss important activity in your account.",
        bullets: const [
          'New orders',
          'Order status updates',
          'New messages',
          'Transaction confirmations',
          'Farmer verification approval or rejection',
          'Important admin notices',
          'Account warnings',
          'Suspension or ban updates',
          'Other important marketplace activity',
          'You can change notification permissions later in your device settings.',
        ],
        denyLabel: 'Not Now',
        allowLabel: 'Enable Notifications',
      );
      if (proceed) {
        try {
          await PushNotificationService().setupFCM();
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
