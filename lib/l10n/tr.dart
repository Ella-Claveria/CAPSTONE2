import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// The app's texts in the current language — English when no translations
/// are loaded above [context] (a widget shown on its own, as in tests), so
/// a text lookup can never fail.
AppLocalizations tr(BuildContext context) =>
    AppLocalizations.of(context) ?? lookupAppLocalizations(const Locale('en'));
