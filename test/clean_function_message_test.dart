// A Cloud Function's message is shown as written, without the HTTP status
// the web SDK can tack on.
import 'package:agritrade/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drops a trailing HTTP status', () {
    expect(
      cleanFunctionMessage(
        'That email is already used by another account. [409]',
      ),
      'That email is already used by another account.',
    );
  });

  test('keeps the message otherwise, and treats blank as none', () {
    expect(cleanFunctionMessage('Incorrect code.'), 'Incorrect code.');
    expect(cleanFunctionMessage('Use [2] tries'), 'Use [2] tries');
    expect(cleanFunctionMessage('  '), isNull);
    expect(cleanFunctionMessage(null), isNull);
  });
}
