import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'screen/app_bootstrap.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_controller.dart';
import 'widgets/connectivity_banner.dart';
import 'services/session_timeout_service.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Tells Flutter to get itself ready before we run any setup code.
  WidgetsFlutterBinding.ensureInitialized();

  // Starts watching for a 15-minute-plus background idle period — see
  // SessionTimeoutService for why this is the only thing that should ever
  // force a signed-in user back to login (a normal close/reopen must not).
  SessionTimeoutService.instance.start(rootNavigatorKey);

  // Draws the first frame immediately (the branded loading screen) instead
  // of waiting on Firebase.initializeApp() first — AppBootstrap does that
  // work in the background, behind the spinner, so there's no dead static
  // gap between tapping the app icon and seeing something load.
  runApp(const AgriTradeApp());
}

class AgriTradeApp extends StatelessWidget {
  const AgriTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when the language picker changes the locale.
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'AgriTrade+',
          navigatorKey: rootNavigatorKey,

          // Hides the red "DEBUG" ribbon in the corner.
          debugShowCheckedModeBanner: false,

          // One line = Montserrat everywhere, plus your green theme.
          theme: AppTheme.themeData(),

          locale: LocaleController.instance.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppBootstrap(),
          // `builder` wraps whatever route the Navigator is currently
          // showing — unlike `home` (which only wraps the FIRST route ever
          // pushed), this keeps running for every screen reached via
          // Navigator.push/pushReplacement/pushAndRemoveUntil afterward,
          // which in practice is almost the entire app (login, role
          // selection, Farmer/Buyer Home, ...). Both ConnectivityBanner and
          // the activity-tracking Listener/Focus below used to live inside
          // `home` instead, which meant they only ever saw AppBootstrap's
          // own brief splash screen — the connectivity banner could never
          // show once the user navigated past boot, and recordActivity()
          // never fired again after the very first route change, so
          // SessionTimeoutService's 15-minute idle timer kept counting
          // down from that single call no matter how much the user kept
          // actively using the app, eventually signing them out from
          // right in the middle of a session. Wrapping the Navigator's
          // own current child here, instead of one specific route's
          // content, is what actually makes both of these span every
          // screen.
          builder: (context, child) {
            return ConnectivityBanner(
              child: Listener(
                onPointerDown: (_) => SessionTimeoutService.instance.recordActivity(),
                onPointerMove: (_) => SessionTimeoutService.instance.recordActivity(),
                onPointerSignal: (_) => SessionTimeoutService.instance.recordActivity(),
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    SessionTimeoutService.instance.recordActivity();
                    return KeyEventResult.ignored;
                  },
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
