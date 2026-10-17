import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'device_trust_service.dart';

/// The "You logged in to AgriTrade+" email, for a farmer or buyer who has
/// just logged in to the mobile app and is now in it.
///
/// The notifySignIn Cloud Function (functions/account_emails.js) sends it
/// to the account's own verified email — the new one, after a Change
/// Email — and decides when not to: a login from a new device already gets
/// the new-device alert, and Admins get the Admin Portal's own alert.
///
/// Only called after a real login (see applyAuthRouteResult's
/// `announceSignIn`), never when an app that is still signed in is opened
/// again.
class SignInAlertService {
  SignInAlertService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// Best effort: never waits on, or gets in the way of, the login.
  static void announce() {
    _send().catchError((Object e) {
      debugPrint('[SignInAlert] not sent: $e');
    });
  }

  static Future<void> _send() async {
    final devices = DeviceTrustService.instance;
    final (platform, deviceName) = await devices.describeDevice();
    final deviceId = await devices.currentDeviceId();
    final result = await _functions
        .httpsCallable('notifySignIn')
        .call<dynamic>({
          'deviceId': deviceId,
          'deviceName': deviceName,
          'platform': platform,
        })
        .timeout(const Duration(seconds: 20));
    debugPrint('[SignInAlert] ${result.data}');
  }
}
