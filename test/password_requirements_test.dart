// The password rules shared by registration and Change Password, and the
// live checklist that shows them.
import 'package:agritrade/widgets/password_requirements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a password must meet every rule', () {
    expect(PasswordRules.meetsAll('badeth123'), isFalse);
    expect(PasswordRules.meetsAll('Badeth1234!'), isFalse); // 11: 12 needed
    expect(PasswordRules.meetsAll('Badeth123456!'), isTrue);
    expect(PasswordRules.meetsAll('BADETH123456!'), isFalse); // lowercase
    expect(PasswordRules.meetsAll('Badethbadeth!'), isFalse); // number
    expect(PasswordRules.meetsAll('Badeth1234567'), isFalse); // symbol
  });

  testWidgets('the checklist is hidden until typing, then marks each rule', (
    tester,
  ) async {
    Future<void> show(String password) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PasswordRequirementsChecklist(password: password)),
      ),
    );

    await show('');
    expect(find.text('Uppercase letter'), findsNothing);

    await show('badeth123');
    for (final label in [
      '12+ characters',
      'Uppercase letter',
      'Lowercase letter',
      'Number',
      'Symbol',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // Lowercase and number met; length, uppercase and symbol not yet.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(3));

    // Every rule met: the list folds away.
    await show('Badeth123456!');
    await tester.pumpAndSettle();
    expect(find.text('Uppercase letter'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    // One no longer met: it is back.
    await show('Badeth123456');
    await tester.pumpAndSettle();
    expect(find.text('Symbol'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
  });
}
