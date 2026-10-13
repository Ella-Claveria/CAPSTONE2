// The E | F (English | Filipino) switch on the login screens: it changes the
// language of the whole app, saves the choice on the device, and is
// introduced by a coach mark the first time only. Onboarding has no switch.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/l10n/locale_controller.dart';
import 'package:agritrade/screen/onboarding_screen.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/agri_dialog.dart';
import 'package:agritrade/widgets/language_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home) => ListenableBuilder(
  listenable: LocaleController.instance,
  builder: (context, _) => MaterialApp(
    locale: LocaleController.instance.locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// A login-like screen: the switch, some translated text, and a way to a
/// second screen.
class Front extends StatelessWidget {
  const Front({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Align(
            alignment: Alignment.topRight,
            child: LanguageToggle(introduce: true),
          ),
          Text(AppLocalizations.of(context)!.loginSubtitle),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const Second()),
            ),
            child: const Text('open second'),
          ),
        ],
      ),
    );
  }
}

class Second extends StatelessWidget {
  const Second({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(AppLocalizations.of(context)!.registerTitle));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the tip shows once, then the switch changes every screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.setLocale(const Locale('en'));
    phone(tester);

    await tester.pumpWidget(app(const Front()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // First time: the coach mark explains the switch.
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Choose your language'),
        matching: find.byType(AgriFrostedCard),
      ),
      findsOneWidget,
    );
    final gotIt = tester.getSize(
      find.widgetWithText(AgriDialogButton, 'Got it'),
    );
    expect(gotIt.height, lessThanOrEqualTo(36));
    expect(gotIt.width, lessThanOrEqualTo(110));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsNothing);

    // Small: just the two letters.
    expect(find.text('E'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(letterBackground(tester, 'E'), AppTheme.dark);
    expect(tester.widget<Text>(find.text('E')).style!.color, Colors.white);
    expect(letterBackground(tester, 'F'), Colors.transparent);
    expect(tester.widget<Text>(find.text('F')).style!.color, AppTheme.dark);
    expect(
      tester.getSize(find.byType(LanguageToggle)).width,
      lessThanOrEqualTo(80),
    );

    expect(find.text('Log in to your AgriTrade+ account'), findsOneWidget);
    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    expect(
      find.text('Mag-log in sa iyong AgriTrade+ account'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language_code'), 'tl');

    // Not just this screen: one opened afterwards is in Filipino too.
    await tester.tap(find.text('open second'));
    await tester.pumpAndSettle();
    expect(find.text('Gumawa ng Account'), findsOneWidget);

    // A later visit to a login screen does not show the tip again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(const Front()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Piliin ang iyong wika'), findsNothing);
    expect(find.text('Choose your language'), findsNothing);

    await tester.tap(find.text('E'));
    await tester.pumpAndSettle();
    expect(find.text('Log in to your AgriTrade+ account'), findsOneWidget);
    expect(prefs.getString('app_language_code'), 'en');
  });

  testWidgets('onboarding has no language switch and no logo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.setLocale(const Locale('en'));
    phone(tester);

    await tester.pumpWidget(app(OnboardingScreen(onGetStarted: () async {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LanguageToggle), findsNothing);
    expect(find.text('Fresh Products, Direct Trading'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/logo.png',
      ),
      findsNothing,
    );
  });
}

// The switch and its tip follow the app's own design: a white pill with the
// active letter on dark green, and the tip on the shared frosted popup card
// with a compact button.
Color? letterBackground(WidgetTester tester, String letter) {
  final box = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(letter),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}
