import 'package:flutter/services.dart';

/// The farmer's RSBA number, asked for on the registration form in place
/// of a certificate upload.
///
/// The accepted length is the client's request: 15–17 characters, letters
/// and numbers only. The form deliberately does not spell the length out —
/// it only says whether what was typed is a valid number. If the Municipal
/// Agriculture Office confirms a different official format, change the two
/// lengths (and [_rsbaAllowed] if other characters turn out to be allowed)
/// here; the field and its validation both read from this file.
///
/// A well-formed number proves nothing about the farmer: it is stored with
/// the registration for the admin to check, and approval stays a manual
/// admin decision.

const int kRsbaMinLength = 15;
const int kRsbaMaxLength = 17;

const String kRsbaLabel = 'RSBA No.';
const String kRsbaHint = 'Enter your RSBA number';
const String kRsbaInvalidMessage = 'Enter a valid RSBA number.';

final RegExp _rsbaAllowed = RegExp(r'[A-Za-z0-9]');

/// Shown where a farmer has no RSBA number on file (an account registered
/// before the number was asked for) — never a made-up ID in its place.
const String kNoFarmerId = 'Not provided';

/// A farmer's Farmer ID: the RSBA number they registered with. It is what
/// the Admin checks before approving the account, and how the farmer is
/// identified in the portal afterwards. Null when none is on file.
///
/// [verification] is the farmer's verificationDocs record, which carries
/// the same number for an application whose profile copy is missing.
String? farmerIdOf(
  Map<String, dynamic>? user, [
  Map<String, dynamic>? verification,
]) {
  for (final source in [user, verification]) {
    final value = normalizeRsba(source?['rsbaNumber']?.toString());
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// How the number is stored: no spaces around it, letters in capitals.
String normalizeRsba(String? raw) => (raw ?? '').trim().toUpperCase();

bool isValidRsba(String? raw) {
  final value = normalizeRsba(raw);
  return value.length >= kRsbaMinLength &&
      value.length <= kRsbaMaxLength &&
      RegExp(r'^[A-Z0-9]+$').hasMatch(value);
}

/// The inline error for the field, or null.
///
/// Nothing is flagged while the number is still being typed: a number that
/// is not valid yet only becomes an error once the field has been left
/// ([touched]) or the form submitted ([submitted]).
String? rsbaError(String? raw, {bool touched = false, bool submitted = false}) {
  final value = normalizeRsba(raw);
  if (value.isEmpty) return submitted ? '$kRsbaLabel is required.' : null;
  if (isValidRsba(value)) return null;
  return touched || submitted ? kRsbaInvalidMessage : null;
}

/// Keeps anything but letters and numbers out of the field, stops at the
/// longest allowed length, and shows letters in capitals.
final List<TextInputFormatter> kRsbaInputFormatters = [
  FilteringTextInputFormatter.allow(_rsbaAllowed),
  LengthLimitingTextInputFormatter(kRsbaMaxLength),
  TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        newValue.copyWith(text: newValue.text.toUpperCase()),
  ),
];
