// The language is chosen inside the app (Settings → Language), not before
// signing in: onboarding has no language switch and no logo.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/l10n/locale_controller.dart';
import 'package:agritrade/screen/onboarding_screen.dart';
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

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('onboarding has no language switch and no logo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.setLocale(const Locale('en'));
    phone(tester);

    await tester.pumpWidget(app(OnboardingScreen(onGetStarted: () async {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('E'), findsNothing);
    expect(find.text('F'), findsNothing);
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
