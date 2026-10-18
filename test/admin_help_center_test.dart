// Help & Support: the FAQ — a search with a category filter beside it,
// each answer opening on a click — and the support contacts, shown only
// once confirmed.
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_help_center.dart';
import 'package:agritrade/services/admin_faq.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('every category has entries, and the payment answer says no', () {
    for (final category in AdminFaqCategory.values) {
      expect(
        kDefaultAdminFaqs.where((f) => f.category == category),
        isNotEmpty,
        reason: category.label,
      );
    }
    expect(
      kDefaultAdminFaqs
          .singleWhere((f) => f.id == 'default-transactions-payments')
          .answer,
      startsWith('No.'),
    );
  });

  test('search words match in any form and order', () {
    expect(adminFaqTerms('Changing passwords'), {'chang', 'password'});
    expect(
      adminFaqTerms('paano palitan ang password'),
      containsAll(['change', 'password']),
    );
    expect(adminFaqTerms('how do I'), isEmpty);
  });

  Future<void> openHelp(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminHelpCenter(
                  context,
                  faqs: Stream.value(kDefaultAdminFaqs),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the category filter beside the search narrows the FAQ; the '
      'search finds answers', (tester) async {
    await openHelp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('How do I change my password?'), findsOneWidget);
    // No chat, and no category buttons: one filter.
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System Maintenance').last);
    await tester.pumpAndSettle();
    expect(find.text('How do I change my password?'), findsNothing);
    expect(find.text('How should technical issues be reported?'), findsOne);

    // Search and filter together: nothing about payments here.
    await tester.enterText(find.byType(TextField).first, 'payments');
    await tester.pumpAndSettle();
    expect(find.text('No matching questions'), findsOneWidget);

    await tester.tap(find.text('System Maintenance').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All categories').last);
    await tester.pumpAndSettle();
    expect(find.text('Does AgriTrade+ directly process payments?'), findsOne);
    // While searching, the answers are open.
    expect(find.textContaining('does not process or hold payments'), findsOne);
  });

  testWidgets('the support team email is shown', (tester) async {
    await openHelp(tester);
    expect(adminSupportContacts.single.value, 'agritrade.team@gmail.com');
    expect(find.textContaining('agritrade.team@gmail.com'), findsWidgets);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('fits a small window', (tester) async {
    await openHelp(tester, size: const Size(420, 700));
    expect(tester.takeException(), isNull);
  });

  test('an imported FAQ with the old wording shows the new one', () {
    const stale = AdminFaq(
      id: 'default-account-password',
      category: AdminFaqCategory.account,
      question: 'How do I change my password?',
      answer:
          'Open your account at the bottom of the sidebar, then Manage '
          'Account › Change Password. Enter your current password and the new '
          'one (at least 6 characters). If you have forgotten your password, '
          'use Forgot Password on the Admin login page instead.',
    );
    expect(refreshStaleDefault(stale).answer, contains('12 characters'));
    // An answer an admin wrote is kept.
    const edited = AdminFaq(
      id: 'default-account-password',
      category: AdminFaqCategory.account,
      question: 'How do I change my password?',
      answer: 'Ask the head admin.',
    );
    expect(refreshStaleDefault(edited).answer, 'Ask the head admin.');
  });
}
