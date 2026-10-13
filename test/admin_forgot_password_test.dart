// The Admin Web sign-in page and its Forgot Password form: one page, with
// the brand panel fixed and only the right-hand form changing. These
// cover the layout at desktop, tablet and small-browser widths, the
// transition between the two forms, and the checks made before anything
// is sent.
import 'package:agritrade/screen/admin_login_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Stands in for the real sign-in form (which needs Firebase): a field to
/// type in and the Forgot Password link.
class FakeSignIn extends StatefulWidget {
  final ValueChanged<String> onForgotPassword;
  const FakeSignIn({super.key, required this.onForgotPassword});

  @override
  State<FakeSignIn> createState() => _FakeSignInState();
}

class _FakeSignInState extends State<FakeSignIn> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Welcome back'),
            TextField(key: const Key('signin-email'), controller: _email),
            TextButton(
              onPressed: () => widget.onForgotPassword(_email.text),
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ),
    );
  }
}

final _signInKey = GlobalKey();

Future<void> pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminAuthShell(
        loginBuilder: (context, narrow, openForgotPassword) =>
            FakeSignIn(key: _signInKey, onForgotPassword: openForgotPassword),
      ),
    ),
  );
}

Future<void> openForgot(WidgetTester tester) async {
  await tester.tap(find.text('Forgot password?'));
  await tester.pumpAndSettle();
  expect(find.text('Forgot Password?'), findsOneWidget);
}

Finder get resetField =>
    find.widgetWithText(TextField, 'Enter your admin email address');

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('desktop: brand panel on the left, compact form on the right', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));
    await openForgot(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AdminBrandPanel), findsOneWidget);
    expect(find.text('Administrative Portal'), findsOneWidget);
    expect(find.text('ADMIN PORTAL'), findsOneWidget);
    expect(find.byTooltip('Back to Login'), findsOneWidget);
    expect(find.textContaining('Spam or Junk folder'), findsOneWidget);

    // The field and the button are the same width, and not stretched.
    final field = tester.getSize(resetField);
    final button = tester.getSize(
      find.widgetWithText(FilledButton, 'Send Reset Link'),
    );
    expect(field.width, button.width);
    expect(field.width, lessThanOrEqualTo(420));
    expect(field.height, inInclusiveRange(48, 50));
    expect(button.height, inInclusiveRange(46, 48));

    // The form sits to the right of the photo.
    final panelRight = tester.getTopRight(find.byType(AdminBrandPanel)).dx;
    expect(tester.getTopLeft(resetField).dx, greaterThan(panelRight));
  });

  testWidgets('tablet and small browsers fit without overflow', (tester) async {
    for (final size in const [
      Size(1024, 768),
      Size(768, 1024),
      Size(360, 640),
    ]) {
      await pumpShell(tester, size);
      expect(tester.takeException(), isNull, reason: 'login at $size');
      await tester.ensureVisible(find.text('Forgot password?'));
      await openForgot(tester);
      expect(tester.takeException(), isNull, reason: 'forgot at $size');
      expect(tester.getSize(resetField).width, lessThanOrEqualTo(size.width));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('only the form moves: the brand panel stays the same widget, '
      'in the same place, through the whole transition', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    final panel = find.byType(AdminBrandPanel);
    final element = tester.element(panel);
    final rect = tester.getRect(panel);

    await tester.tap(find.text('Forgot password?'));
    // Frame by frame through the 250 ms change.
    var sawBoth = false;
    for (var ms = 0; ms <= 300; ms += 25) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
      expect(tester.element(panel), same(element));
      expect(tester.getRect(panel), rect);
      if (find.text('Welcome back').evaluate().isNotEmpty &&
          find.text('Forgot Password?').evaluate().isNotEmpty) {
        sawBoth = true; // cross-fading
      }
    }
    expect(sawBoth, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);

    // The form is centred in the right-hand area.
    final area = Rect.fromLTRB(rect.right, 0, 1440, 900);
    expect(
      tester.getCenter(resetField).dx,
      moreOrLessEquals(area.center.dx, epsilon: 1),
    );

    // And back.
    await tester.tap(find.byTooltip('Back to Login'));
    for (var ms = 0; ms <= 300; ms += 25) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.element(panel), same(element));
      expect(tester.getRect(panel), rect);
    }
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsNothing);
  });

  testWidgets('what was typed in the login form is still there on return, '
      'and is carried into the reset form', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    await tester.enterText(
      find.byKey(const Key('signin-email')),
      'someone@lgu.gov.ph',
    );
    await openForgot(tester);
    expect(
      tester.widget<TextField>(resetField).controller!.text,
      'someone@lgu.gov.ph',
    );
    await tester.tap(find.byTooltip('Back to Login'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('signin-email')))
          .controller!
          .text,
      'someone@lgu.gov.ph',
    );
  });

  testWidgets('the reset form starts empty when nothing was typed, and '
      'starts fresh each time it is opened', (tester) async {
    await pumpShell(tester, const Size(1440, 900));
    await openForgot(tester);
    expect(tester.widget<TextField>(resetField).controller!.text, '');
    await tester.enterText(resetField, 'not an email');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Login'));
    await tester.pumpAndSettle();
    await openForgot(tester);
    expect(tester.widget<TextField>(resetField).controller!.text, '');
    expect(find.text('Enter a valid email address.'), findsNothing);
  });

  testWidgets('an invalid email is refused on the page, nothing is sent', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));
    await openForgot(tester);
    for (final bad in ['', 'admin', 'admin@site', 'a b@site.com']) {
      await tester.enterText(resetField, bad);
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      // Still the form: no confirmation, no loading state.
      expect(find.text('Check Your Email'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });

  testWidgets('the browser Back button returns to the login form', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));
    await openForgot(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsNothing);
    expect(find.byType(AdminBrandPanel), findsOneWidget);
  });

  testWidgets('resizing past the breakpoint keeps the open form', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));
    await openForgot(tester);
    await tester.enterText(resetField, 'half@typed');
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<TextField>(resetField).controller!.text, 'half@typed');
  });
}
