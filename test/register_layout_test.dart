// Where the Register button, the "complete all fields" hint and the log-in
// link sit on the registration form: the button floats while the end of the
// form is off screen, and rests above the hint and the link once it is not.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const hint = 'Please complete all fields first.';

Finder get registerButton => find.widgetWithText(ElevatedButton, 'Register');
Finder get loginLink => find.textContaining('Log in', findRichText: true);

Future<void> pumpForm(WidgetTester tester, {String role = 'farmer'}) async {
  // Wide, because the test font is much wider than Montserrat.
  tester.view.physicalSize = const Size(600, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RegisterScreen(initialRole: role),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('at the top, only the Register button is on screen', (
    tester,
  ) async {
    await pumpForm(tester);
    final button = tester.getRect(registerButton);
    expect(button.bottom, closeTo(720 - 6, 1));
    // The hint and the link are further down the form.
    expect(tester.getRect(find.text(hint)).top, greaterThan(720));
    expect(tester.getRect(loginLink).top, greaterThan(720));
  });

  testWidgets('at the end, the button rests above the hint and the link', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();

    final button = tester.getRect(registerButton);
    final hintRect = tester.getRect(find.text(hint));
    final link = tester.getRect(loginLink);
    expect(button.bottom, lessThanOrEqualTo(hintRect.top));
    expect(hintRect.bottom, lessThanOrEqualTo(link.top));
    expect(link.bottom, lessThanOrEqualTo(720));
    // Nothing above it is covered either.
    final terms = tester.getRect(
      find.textContaining('I agree to the', findRichText: true),
    );
    expect(terms.bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('scrolling back up floats the button again', (tester) async {
    await pumpForm(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(registerButton).bottom, closeTo(720 - 6, 1));
  });

  testWidgets('the buyer form ends the same way', (tester) async {
    await pumpForm(tester, role: 'buyer');
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    final button = tester.getRect(registerButton);
    expect(
      button.bottom,
      lessThanOrEqualTo(tester.getRect(find.text(hint)).top),
    );
    expect(tester.getRect(loginLink).bottom, lessThanOrEqualTo(720));
  });

  testWidgets('the farmer form is in the agreed order', (tester) async {
    await pumpForm(tester);
    double top(Finder finder) => tester.getRect(finder).top;
    final order = [
      top(find.text('Full Name')),
      top(find.text('RSBA No.')),
      top(find.text('Email Address')),
      top(find.text('Mobile Number')),
      top(find.text('Password')),
      top(find.text('Confirm Password')),
      top(find.text('Only farmers from Laurel, Batangas may register.')),
      top(find.text('Barangay (Laurel)')),
      top(find.textContaining('Supported Products', findRichText: true)),
      top(find.textContaining('I agree to the', findRichText: true)),
    ];
    expect(order, orderedEquals([...order]..sort()));
  });

  testWidgets('a buyer sees none of the farmer-only parts', (tester) async {
    await pumpForm(tester, role: 'buyer');
    expect(find.text('RSBA No.'), findsNothing);
    expect(find.textContaining('Only farmers from Laurel'), findsNothing);
    expect(find.text('Barangay (Laurel)'), findsNothing);
    expect(
      find.textContaining('Supported Products', findRichText: true),
      findsNothing,
    );
    // Required for buyers too, so no "(optional)".
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Mobile Number (optional)'), findsNothing);
  });
}
