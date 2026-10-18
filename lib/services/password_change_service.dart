import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart' show cleanFunctionMessage;

/// What asking for a password change code came back with.
class PasswordCodeRequest {
  final bool sent;
  final int resendAfterSeconds;

  /// A message to show instead, when nothing was sent.
  final String? error;

  const PasswordCodeRequest({
    this.sent = false,
    this.resendAfterSeconds = 0,
    this.error,
  });
}

/// Change Password with a code: the current password is re-entered, a
/// 6-digit code goes to the account's own email
/// (requestPasswordChangeOtp), and with that code the server changes the
/// password, signs the account out everywhere else and emails a notice
/// (confirmPasswordChangeOtp). This device is then signed straight back in
/// with the new password.
class PasswordChangeService {
  PasswordChangeService({FirebaseFunctions? functions, FirebaseAuth? auth})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Where the code goes: the signed-in account's own email.
  String get email => _auth.currentUser?.email ?? '';

  /// Checks [currentPassword] (when given — Resend leaves it out), then
  /// emails a code to the account.
  Future<PasswordCodeRequest> requestCode({String? currentPassword}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      return const PasswordCodeRequest(error: 'Please log in again.');
    }
    try {
      if (currentPassword != null) {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: currentPassword),
        );
      }
      final response = await _functions
          .httpsCallable('requestPasswordChangeOtp')
          .call<dynamic>();
      final data = response.data is Map ? response.data as Map : const {};
      return PasswordCodeRequest(
        sent: data['sent'] == true,
        resendAfterSeconds: (data['resendAfterSeconds'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseAuthException catch (e) {
      return PasswordCodeRequest(
        error: switch (e.code) {
          'wrong-password' ||
          'invalid-credential' ||
          'user-mismatch' => 'Current password is incorrect.',
          'too-many-requests' =>
            'Too many attempts. Please wait a bit and try again.',
          'network-request-failed' =>
            'No internet connection. Please check your connection and try again.',
          _ => 'Could not check your current password. Please try again.',
        },
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('requestPasswordChangeOtp failed: ${e.code} ${e.message}');
      final details = e.details;
      return PasswordCodeRequest(
        error: switch (e.code) {
          'resource-exhausted' ||
          'failed-precondition' ||
          'unavailable' ||
          'permission-denied' =>
            cleanFunctionMessage(e.message) ?? 'Please try again.',
          'unauthenticated' => 'Your session has expired. Please log in again.',
          'not-found' =>
            'Changing your password is not available yet. Please try again '
                'later.',
          _ => 'Could not send the verification code. Please try again.',
        },
        resendAfterSeconds: details is Map
            ? (details['retryAfterSeconds'] as num?)?.toInt() ?? 0
            : 0,
      );
    } catch (e) {
      debugPrint('requestPasswordChangeOtp failed: $e');
      return const PasswordCodeRequest(
        error: 'Could not send the verification code. Please try again.',
      );
    }
  }

  /// Null once the password is changed (and this device signed back in
  /// with it), or a message to show.
  Future<String?> confirm({
    required String code,
    required String newPassword,
  }) async {
    final email = _auth.currentUser?.email;
    if (email == null) return 'Please log in again.';
    try {
      await _functions.httpsCallable('confirmPasswordChangeOtp').call<dynamic>({
        'code': code.replaceAll(RegExp(r'\s'), ''),
        'newPassword': newPassword,
      });
    } on FirebaseFunctionsException catch (e) {
      return switch (e.code) {
        'invalid-argument' ||
        'failed-precondition' ||
        'resource-exhausted' ||
        'unavailable' ||
        'permission-denied' =>
          cleanFunctionMessage(e.message) ?? 'Incorrect verification code.',
        'unauthenticated' => 'Please log in again.',
        _ => 'Could not change your password. Please try again.',
      };
    } catch (_) {
      return 'Could not change your password. Please try again.';
    }
    // The other sessions were ended; keep this one going.
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: newPassword,
      );
    } catch (e) {
      debugPrint('Sign-in after password change failed: $e');
    }
    return null;
  }
}
