import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'screen/app_bootstrap.dart';
import 'l10n/app_localizations.dart';
import 'widgets/app_scaffold_messenger.dart';
import 'widgets/connectivity_banner.dart';
import 'services/account_status_watcher.dart';
import 'services/session_timeout_service.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Tells Flutter to get itself ready before we run any setup code.
  WidgetsFlutterBinding.ensureInitialized();

  // Starts watching for a 30-day-plus background inactivity period — see
  // SessionTimeoutService for why this is the only thing that should ever
  // force a signed-in user back to login (a normal close/reopen must not).
  SessionTimeoutService.instance.start(rootNavigatorKey);

  // Signs a buyer or farmer out, with the reason, as soon as an Admin
  // suspends or bans the account while the app is open.
  AccountStatusWatcher.instance.start(rootNavigatorKey);

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
    return MaterialApp(
      title: 'AgriTrade+',
      navigatorKey: rootNavigatorKey,

      // Hides the red "DEBUG" ribbon in the corner.
      debugShowCheckedModeBanner: false,

      // One line = Montserrat everywhere, plus your green theme.
      theme: AppTheme.themeData(),
      // Light only — the app has no dark mode.
      themeMode: ThemeMode.light,

      // English only. The texts still come from the translation files
      // (lib/l10n), so a Filipino version can be added later by
      // translating app_tl.arb and offering a language choice again.
      locale: const Locale('en'),
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
            onPointerDown: (_) =>
                SessionTimeoutService.instance.recordActivity(),
            onPointerMove: (_) =>
                SessionTimeoutService.instance.recordActivity(),
            onPointerSignal: (_) =>
                SessionTimeoutService.instance.recordActivity(),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                SessionTimeoutService.instance.recordActivity();
                return KeyEventResult.ignored;
              },
              // Every message (SnackBar): 2 seconds, and the newest
              // replaces the one showing (AppScaffoldMessenger).
              child: AppScaffoldMessenger(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
