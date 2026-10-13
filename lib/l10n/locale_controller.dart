import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the mobile app's language (English or Tagalog) and notifies
/// MaterialApp to rebuild when it changes. Call
/// LocaleController.instance.setLocale(...) from anywhere (the language
/// toggle on onboarding/login, the Settings screens) to switch at runtime.
///
/// The choice is saved on the device rather than on the account, so it
/// already applies before login and survives a logout. Until one is made,
/// the app follows the phone's own language.
///
/// The web Admin Portal is English only: there the locale never changes.
class LocaleController extends ChangeNotifier {
  LocaleController._() {
    if (!kIsWeb) {
      _locale = _fromDevice();
      _load();
    }
  }
  static final LocaleController instance = LocaleController._();

  static const _key = 'app_language_code';
  static const _english = Locale('en');
  static const _tagalog = Locale('tl');

  Locale _locale = _english;

  Locale get locale => _locale;

  /// 'en' or 'tl'.
  String get languageCode => _locale.languageCode;

  bool get isTagalog => _locale == _tagalog;

  // Android and iOS report Filipino as 'fil' and Tagalog as 'tl'.
  static Locale _fromDevice() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return code == 'tl' || code == 'fil' ? _tagalog : _english;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == null) return;
      final locale = saved == 'tl' ? _tagalog : _english;
      if (locale == _locale) return;
      _locale = locale;
      notifyListeners();
    } catch (_) {
      // Keep the phone's language.
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (kIsWeb) return;
    final next = locale.languageCode == 'tl' ? _tagalog : _english;
    if (next != _locale) {
      _locale = next;
      notifyListeners();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next.languageCode);
    } catch (_) {
      // Still applies for this run.
    }
  }
}
