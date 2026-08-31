import 'package:flutter/material.dart';

/// Holds the app's current locale and notifies MaterialApp to rebuild
/// when it changes. Call LocaleController.instance.setLocale(...)
/// from anywhere (e.g. a settings screen) to switch language at runtime.
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  Locale? _locale; // null = follow system locale

  Locale? get locale => _locale;

  void setLocale(Locale? locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
  }
}