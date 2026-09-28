import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';

/// Account settings for the buyer's Profile tab. Currently just language —
/// the same LocaleController/AppLocalizations picker already used from the
/// marketplace app bar, surfaced here too so it lives somewhere discoverable
/// under Profile rather than only as a top-bar icon.
class BuyerSettingsScreen extends StatelessWidget {
  const BuyerSettingsScreen({super.key});

  static const Color _dark = Color(0xFF1B5E20);

  void _showLanguagePicker(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final currentCode = LocaleController.instance.locale?.languageCode ?? 'en';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.selectLanguage,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              RadioGroup<String>(
                groupValue: currentCode,
                onChanged: (value) {
                  if (value == null) return;
                  LocaleController.instance.setLocale(Locale(value));
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: _dark,
                      content: Text(
                        AppLocalizations.of(context)!
                            .languageChanged(value == 'en' ? t.english : t.tagalog),
                      ),
                    ),
                  );
                },
                child: Column(
                  children: [
                    RadioListTile<String>(title: Text(t.english), value: 'en', activeColor: _dark),
                    RadioListTile<String>(title: Text(t.tagalog), value: 'tl', activeColor: _dark),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: const Text('Account Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.language, color: _dark),
            title: const Text('Language'),
            subtitle: ListenableBuilder(
              listenable: LocaleController.instance,
              builder: (context, _) {
                final code = LocaleController.instance.locale?.languageCode ?? 'en';
                return Text(code == 'tl' ? 'Tagalog' : 'English');
              },
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _showLanguagePicker(context),
          ),
        ],
      ),
    );
  }
}
