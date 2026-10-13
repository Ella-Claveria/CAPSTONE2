import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What already exists for an email someone is about to register.
enum ExistingAccount {
  /// Nothing: registration may go ahead.
  none,

  /// A farmer whose application is waiting for the office's review.
  farmerPending,

  /// An approved farmer.
  farmerApproved,

  /// A farmer whose application was not approved.
  farmerRejected,

  /// Any other account (a buyer, or a registration that was started and
  /// not finished).
  registered,
}

/// The server's one-word answer (functions/registration_status.js) as an
/// [ExistingAccount]. Anything unrecognized is [ExistingAccount.none], so
/// an unexpected answer never blocks a registration.
ExistingAccount existingAccountFromStatus(Object? status) => switch (status) {
  'farmer_pending' => ExistingAccount.farmerPending,
  'farmer_approved' => ExistingAccount.farmerApproved,
  'farmer_rejected' => ExistingAccount.farmerRejected,
  'registered' => ExistingAccount.registered,
  _ => ExistingAccount.none,
};

/// Trimmed and lowercased, so "Juan@Gmail.com " and "juan@gmail.com" are
/// the same account.
String normalizeEmail(String email) => email.trim().toLowerCase();

/// Stops a second registration from being started for an account that
/// already exists — the farmer who registered, went "Back to login" to
/// wait for approval, and then taps "Create one" again.
///
/// It does not create or change anything. A duplicate account is already
/// impossible (Firebase Authentication allows one account per email, and
/// every profile is keyed by that account's uid); this only finds out
/// early, so the person is told where their application stands and sent
/// to Login instead of filling the form in a second time.
class RegistrationGuard {
  RegistrationGuard._();

  static const String _emailKey = 'last_account_email';

  static final _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// Remembers, on this phone, the email of the account last registered
  /// or signed in to here — what "Create one" is checked against, since
  /// nobody is signed in at that point.
  static Future<void> remember(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emailKey, normalized);
    } catch (_) {}
  }

  static Future<String?> remembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      return email == null || email.isEmpty ? null : email;
    } catch (_) {
      return null;
    }
  }

  /// What already exists for [email]. [ExistingAccount.none] when the
  /// check itself cannot be made (offline, the function unavailable):
  /// registration then goes ahead as before, and Firebase Authentication
  /// still refuses an email that is taken.
  static Future<ExistingAccount> check(String email) async {
    final normalized = normalizeEmail(email);
    if (normalized.isEmpty) return ExistingAccount.none;
    try {
      final result = await _functions
          .httpsCallable('registrationStatus')
          .call({'email': normalized})
          .timeout(const Duration(seconds: 8));
      final data = result.data;
      return existingAccountFromStatus(data is Map ? data['status'] : null);
    } catch (error) {
      debugPrint('[RegistrationGuard] could not check $normalized: $error');
      return ExistingAccount.none;
    }
  }
}
