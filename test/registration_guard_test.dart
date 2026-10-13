import 'package:agritrade/services/registration_guard.dart';
import 'package:agritrade/widgets/existing_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an email is compared trimmed and lowercased', () {
    expect(
      normalizeEmail('  Juan.DelaCruz@Gmail.com '),
      'juan.delacruz@gmail.com',
    );
  });

  test('the server\'s answer becomes what already exists', () {
    expect(existingAccountFromStatus('none'), ExistingAccount.none);
    expect(
      existingAccountFromStatus('farmer_pending'),
      ExistingAccount.farmerPending,
    );
    expect(
      existingAccountFromStatus('farmer_approved'),
      ExistingAccount.farmerApproved,
    );
    expect(
      existingAccountFromStatus('farmer_rejected'),
      ExistingAccount.farmerRejected,
    );
    expect(existingAccountFromStatus('registered'), ExistingAccount.registered);
    // Never blocks a registration on an answer it does not understand.
    expect(existingAccountFromStatus(null), ExistingAccount.none);
    expect(existingAccountFromStatus('something else'), ExistingAccount.none);
  });

  test('each case has its own title and message', () {
    final pending = existingAccountCopy(ExistingAccount.farmerPending);
    expect(pending.title, 'Application already submitted');
    expect(
      pending.message,
      'Your Farmer application is already under review. Please log in '
      'to check your application status.',
    );
    expect(pending.cancellable, isTrue);

    final approved = existingAccountCopy(ExistingAccount.farmerApproved);
    expect(approved.title, 'Account already registered');
    expect(
      approved.message,
      'This email is already registered as an approved Farmer. Please '
      'log in to continue.',
    );
    expect(approved.cancellable, isFalse);

    expect(
      existingAccountCopy(ExistingAccount.farmerRejected).message,
      contains('not approved'),
    );
  });

  Future<ExistingAccountChoice?> open(
    WidgetTester tester,
    ExistingAccount account, {
    required String tap,
    bool offerDifferentEmail = false,
  }) async {
    ExistingAccountChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showExistingAccountDialog(
              context,
              account,
              offerDifferentEmail: offerDifferentEmail,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('a pending farmer is offered Cancel and Go to Login', (
    tester,
  ) async {
    expect(
      await open(tester, ExistingAccount.farmerPending, tap: 'Cancel'),
      ExistingAccountChoice.cancel,
    );
    expect(
      await open(tester, ExistingAccount.farmerPending, tap: 'Go to Login'),
      ExistingAccountChoice.login,
    );
  });

  testWidgets('an approved farmer is offered only Go to Login', (tester) async {
    ExistingAccountChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showExistingAccountDialog(
              context,
              ExistingAccount.farmerApproved,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Account already registered'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Go to Login'));
    await tester.pumpAndSettle();
    expect(choice, ExistingAccountChoice.login);
  });

  testWidgets('someone else on the same phone can still register', (
    tester,
  ) async {
    expect(
      await open(
        tester,
        ExistingAccount.farmerPending,
        tap: 'Register a different email',
        offerDifferentEmail: true,
      ),
      ExistingAccountChoice.differentEmail,
    );
  });
}
