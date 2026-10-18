// The mobile app's Help & Support: the role's own FAQ (answers open on
// tap), the shared questions, and the support email.
import 'package:agritrade/data/mobile_faqs.dart';
import 'package:agritrade/screen/help_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('a farmer sees farmer questions and the support email', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: HelpSupportScreen(farmer: true)),
    );
    expect(find.text('How do I post a product?'), findsOneWidget);
    expect(find.text('How do I place an order?'), findsNothing);
    expect(find.text(kSupportEmail), findsOneWidget);

    await tester.tap(find.text('How do I change my password?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 12 characters'), findsOneWidget);
  });

  test('a buyer gets buyer questions, the shared ones last', () {
    final faqs = mobileFaqsFor(farmer: false);
    expect(faqs.first.question, 'How do I place an order?');
    expect(faqs.last.question, 'How can I contact support?');
    expect(faqs.last.answer, contains('agritrade.team@gmail.com'));
    expect(faqs.any((f) => f.question == 'How do I post a product?'), isFalse);
  });
}
