import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart' show cleanFunctionMessage;

/// What asking for a recovery email code came back with.
class RecoveryCodeRequest {
  /// Already verified, no code needed (the server no longer answers this
  /// way, but the dialog still handles it).
  final bool verified;

  /// A code was emailed.
  final bool sent;

  /// Seconds before another code can be asked for.
  final int resendAfterSeconds;

  /// A message to show instead, when nothing was sent.
  final String? error;

  const RecoveryCodeRequest({
    this.verified = false,
    this.sent = false,
    this.resendAfterSeconds = 0,
    this.error,
  });
}

/// Verifies a Farmer's or Buyer's recovery email with a 6-digit code
/// emailed to it (the requestRecoveryEmailOtp / confirmRecoveryEmailOtp
/// Cloud Functions). The functions save the address and its
/// recoveryEmailVerified flag on users/{uid}; the app only reads them, so
/// "Verified" always means the code was entered. The sign-in email is
/// never touched.
class RecoveryEmailService {
  RecoveryEmailService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  /// Saves [email] as the recovery email (not verified yet) and emails it
  /// a code.
  Future<RecoveryCodeRequest> requestCode(String email) async {
    try {
      final response = await _functions
          .httpsCallable('requestRecoveryEmailOtp')
          .call<dynamic>({'email': email.trim()});
      final data = response.data is Map ? response.data as Map : const {};
      return RecoveryCodeRequest(
        verified: data['verified'] == true,
        sent: data['sent'] == true,
        resendAfterSeconds: (data['resendAfterSeconds'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('requestRecoveryEmailOtp failed: ${e.code} ${e.message}');
      final details = e.details;
      return RecoveryCodeRequest(
        error: switch (e.code) {
          'invalid-argument' ||
          'resource-exhausted' ||
          'unavailable' ||
          'permission-denied' =>
            cleanFunctionMessage(e.message) ?? 'Please try again.',
          'unauthenticated' => 'Your session has expired. Please log in again.',
          'not-found' =>
            'Verifying a recovery email is not available yet. Please try '
                'again later.',
          _ => 'Could not send the verification code. Please try again.',
        },
        resendAfterSeconds: details is Map
            ? (details['retryAfterSeconds'] as num?)?.toInt() ?? 0
            : 0,
      );
    } catch (e) {
      debugPrint('requestRecoveryEmailOtp failed: $e');
      return const RecoveryCodeRequest(
        error: 'Could not send the verification code. Please try again.',
      );
    }
  }

  /// Null once the recovery email is verified, or a message to show.
  Future<String?> confirmCode(String code) async {
    try {
      await _functions.httpsCallable('confirmRecoveryEmailOtp').call<dynamic>({
        'code': code.replaceAll(RegExp(r'\s'), ''),
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return switch (e.code) {
        'invalid-argument' ||
        'failed-precondition' ||
        'resource-exhausted' ||
        'permission-denied' =>
          cleanFunctionMessage(e.message) ?? 'Incorrect verification code.',
        'unauthenticated' => 'Please log in again.',
        _ => 'Could not verify the code. Please try again.',
      };
    } catch (_) {
      return 'Could not verify the code. Please try again.';
    }
  }
}
