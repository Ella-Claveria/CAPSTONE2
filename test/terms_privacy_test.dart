// Terms & Privacy: the Admin Portal's three-tab popup, and the mobile
// screens farmers and buyers open at registration — both from the same
// policy text (lib/data/legal_policies.dart).
import 'package:agritrade/data/legal_policies.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_info_dialogs.dart';
import 'package:agritrade/screen/privacy_policy_screen.dart';
import 'package:agritrade/screen/terms_and_conditions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> openDialog(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminTermsPrivacy(context),
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

  testWidgets('three tabs, each with its own document, dates and version; '
      'Close stays in reach while the text scrolls', (tester) async {
    await openDialog(tester, const Size(1280, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Terms & Privacy'), findsOneWidget);
    for (final tab in [
      'Terms of Service',
      'Privacy Policy',
      'Admin Guidelines',
    ]) {
      expect(find.widgetWithText(Tab, tab), findsOneWidget);
    }

    // Terms of Service first, with the AI price disclaimer.
    expect(find.text(kTermsOfService.effectiveLabel), findsOneWidget);
    expect(find.text('Version ${kTermsOfService.version}'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('6. AI-Assisted Price Recommendations and Their Limitations'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Terms & Privacy'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Privacy Policy'));
    await tester.pumpAndSettle();
    expect(find.text('Version ${kPrivacyPolicy.version}'), findsOneWidget);
    expect(find.text('1. Personal Information Collected'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Admin Guidelines'));
    await tester.pumpAndSettle();
    expect(find.text('Internal — for administrators only'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Terms & Privacy'), findsNothing);
  });

  testWidgets('fits a small window', (tester) async {
    await openDialog(tester, const Size(420, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('registration opens the same documents', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: TermsAndConditionsScreen()),
    );
    expect(find.text('AgriTrade+ Terms of Service'), findsOneWidget);
    expect(find.textContaining(kTermsOfService.effectiveLabel), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));
    expect(find.text('AgriTrade+ Privacy Policy'), findsOneWidget);
  });

  test('no date is made up; the contact is the team support email', () {
    for (final doc in [kTermsOfService, kPrivacyPolicy, kAdminGuidelines]) {
      expect(doc.effectiveDate, isNull, reason: doc.title);
      expect(doc.lastUpdated, isNull, reason: doc.title);
    }
    expect(kPolicyContact, contains('agritrade.team@gmail.com'));
    expect(kPolicyOperator, 'the AgriTrade+ Team');
    expect(kPolicyPrivacyOfficer, contains('agritrade.team@gmail.com'));
  });
}
