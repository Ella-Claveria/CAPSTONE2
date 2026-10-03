import 'package:agritrade/services/ph_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

String typed(String text) => const PhMobileInputFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
    .text;

void main() {
  test('every stored format shows as the same 10 digits', () {
    for (final stored in [
      '09123456789',
      '639123456789',
      '+639123456789',
      '+63 912 345 6789',
      '9123456789',
      '0912-345-6789',
    ]) {
      expect(phMobileLocalDigits(stored), '9123456789', reason: stored);
    }
  });

  test('empty, null and partial numbers are left as they are', () {
    expect(phMobileLocalDigits(null), '');
    expect(phMobileLocalDigits(''), '');
    expect(phMobileLocalDigits('912'), '912');
    // A number being typed that happens to start with 0 or 63 is not
    // mistaken for a prefix until it is long enough to be one.
    expect(phMobileLocalDigits('0912'), '0912');
    expect(phMobileLocalDigits('6391'), '6391');
  });

  test('stored form is always +63 and 10 digits', () {
    expect(phMobileE164('9123456789'), '+639123456789');
    expect(phMobileE164(''), '');
  });

  test('valid means exactly 10 digits starting with 9', () {
    expect(isValidPhMobile('9123456789'), isTrue);
    expect(isValidPhMobile('912345678'), isFalse);
    expect(isValidPhMobile('91234567890'), isFalse);
    expect(isValidPhMobile('8123456789'), isFalse);
    expect(isValidPhMobile('91234abcde'), isFalse);
  });

  test('the field accepts digits only, and no more than 10', () {
    expect(typed('9123456789012'), '9123456789');
    expect(typed('91a2 3-4+5'), '912345');
    expect(typed('abc'), '');
  });

  test('a pasted full number keeps the right 10 digits', () {
    expect(typed('+63 912 345 6789'), '9123456789');
    expect(typed('09123456789'), '9123456789');
  });

  test('errors: wrong first digit at once, the rest after submitting', () {
    String? error(
      String digits, {
      bool required = true,
      bool submitted = false,
    }) => phMobileError(digits, required: required, submitted: submitted);

    expect(error('8'), kPhMobileInvalidMessage);
    // Still typing — not an error yet.
    expect(error('912'), isNull);
    expect(error('912', submitted: true), kPhMobileInvalidMessage);
    expect(error('', submitted: true), 'Mobile number is required.');
    expect(error('', required: false, submitted: true), isNull);
    expect(error('9123456789', submitted: true), isNull);
  });
}
