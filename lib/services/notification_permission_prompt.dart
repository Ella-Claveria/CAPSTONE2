import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import '../widgets/permission_rationale_dialog.dart';

/// Watches for the very first tap a logged-in user makes anywhere in the
/// app and, if this device has never been asked before, that tap is the
/// moment we explain and request notification access — rather than
/// surprising a brand-new user with a system dialog before they've done
/// anything, or waiting until they happen to open the Notifications screen.
class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();
  static final instance = NotificationPermissionPrompt._();

  static const _askedKey = 'asked_notification_permission';

  bool _handling = false;

  Future<void> maybeHandleFirstTap(BuildContext? context) async {
    if (_handling || context == null) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _handling = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final asked = prefs.getBool(_askedKey) ?? false;
      if (asked) return;
      await prefs.setBool(_askedKey, true);

      if (!context.mounted) return;
      final proceed = await showPermissionRationale(
        context,
        icon: Icons.notifications_active_outlined,
        title: 'Stay in the loop',
        message: 'Turn on notifications so AgriTrade+ can alert you about new '
            'messages, order updates, and verification status the moment they happen.',
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
