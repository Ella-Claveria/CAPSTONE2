import 'package:agritrade/services/email_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the first three characters and the domain', () {
    expect(maskEmail('agritrade@gmail.com'), 'agr***@gmail.com');
    expect(maskEmail('  juan.delacruz@yahoo.com '), 'jua***@yahoo.com');
  });

  test('a short local part shows only its first character', () {
    expect(maskEmail('abc@gmail.com'), 'a***@gmail.com');
    expect(maskEmail('a@gmail.com'), 'a***@gmail.com');
  });

  test('something that is not an email is left alone', () {
    expect(maskEmail(''), '');
    expect(maskEmail('not-an-email'), 'not-an-email');
  });
}
