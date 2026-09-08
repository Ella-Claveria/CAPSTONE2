import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'screen/app_bootstrap.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_controller.dart';
import 'widgets/connectivity_banner.dart';
import 'services/notification_permission_prompt.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  // Tells Flutter to get itself ready before we run any setup code.
  WidgetsFlutterBinding.ensureInitialized();

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

          // One line = Inter everywhere, plus your green theme.
          theme: AppTheme.themeData(),

          locale: LocaleController.instance.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,

          // A brand-new, never-asked user gets the notification-permission
          // explanation on their very first tap anywhere in the app — not
          // tied to any one screen — rather than at launch (too early) or
          // only when they happen to open Notifications (too late/hidden).
          builder: (context, child) {
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => NotificationPermissionPrompt.instance
                  .maybeHandleFirstTap(rootNavigatorKey.currentContext),
              child: child,
            );
          },

          home: const ConnectivityBanner(child: AppBootstrap()),
        );
      },
    );
  }
}
