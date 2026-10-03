import 'package:flutter/services.dart';

/// Philippine mobile numbers, handled the same way everywhere the app asks
/// for one (Registration, Google sign-up, Personal Information, Place
/// Order): the field shows a fixed "+63" and holds only the 10 digits after
/// it; what is stored is always "+639XXXXXXXXX".

const String kPhMobilePrefix = '+63 ';
const String kPhMobileHint = '9123456789';
const String kPhMobileInvalidMessage = 'Enter a valid Philippine mobile number.';

/// The 10 digits after +63 from a number in any of the forms it may have
/// been saved or pasted in — "09123456789", "639123456789",
/// "+63 912 345 6789", "9123456789" — or as many of them as there are.
/// Never more than 10 digits, never anything but digits.
String phMobileLocalDigits(String? raw) {
  var digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 12 && digits.startsWith('63')) {
    digits = digits.substring(2);
  } else if (digits.length >= 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

/// Exactly 10 digits, starting with 9.
bool isValidPhMobile(String localDigits) =>
    RegExp(r'^9[0-9]{9}$').hasMatch(localDigits);

/// How the number is stored: "+639123456789". Empty in, empty out.
String phMobileE164(String localDigits) =>
    localDigits.isEmpty ? '' : '+63$localDigits';

/// The inline error for a mobile field holding [localDigits], or null.
///
/// A wrong first digit is flagged straight away; "required" and "not all
/// 10 digits yet" only once the form has been submitted ([submitted]), so
/// a number still being typed never looks like a mistake.
String? phMobileError(
  String localDigits, {
  required bool required,
  required bool submitted,
}) {
  if (localDigits.isEmpty) {
    return required && submitted ? 'Mobile number is required.' : null;
  }
  if (!localDigits.startsWith('9')) return kPhMobileInvalidMessage;
  if (localDigits.length != 10 && submitted) return kPhMobileInvalidMessage;
  return null;
}

/// Keeps a mobile field to at most 10 digits and nothing else — no
/// letters, symbols, spaces or an 11th digit. A whole number pasted in
/// with its country code or leading zero ("+63 912…", "0912…") is reduced
/// to its 10 local digits rather than cut off in the wrong place.
class PhMobileInputFormatter extends TextInputFormatter {
  const PhMobileInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = phMobileLocalDigits(newValue.text);
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

const List<TextInputFormatter> kPhMobileInputFormatters = [
  PhMobileInputFormatter(),
];
