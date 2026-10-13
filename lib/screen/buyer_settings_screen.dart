import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/change_password_dialog.dart';
import 'buyer_privacy_security_screen.dart';
import 'buyer_saved_products_screen.dart' show buyerSubScreenAppBar;
import 'buyer_support_screen.dart';
import 'farmer_edit_profile_screen.dart';

/// Account Settings, opened from the buyer's Profile tab: Personal
/// Information, Change Password, Privacy & Security and Help & Support —
/// the account actions that used to sit in the Profile's popup menu, which
/// is why none of them appears on the Profile page itself. Language and
/// Dark mode follow as app preferences.
class BuyerSettingsScreen extends StatelessWidget {
  const BuyerSettingsScreen({super.key});

  static const Color _dark = AppTheme.dark;

  void _showLanguagePicker(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final currentCode = LocaleController.instance.languageCode;
    showAgriSheet<void>(
      context: context,
      title: t.selectLanguage,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: currentCode,
              onChanged: (value) {
                if (value == null) return;
                LocaleController.instance.setLocale(Locale(value));
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: _dark,
                    content: Text(
                      AppLocalizations.of(
                        context,
                      )!.languageChanged(value == 'en' ? t.english : t.tagalog),
                    ),
                  ),
                );
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Text(t.english),
                    value: 'en',
                    activeColor: _dark,
                  ),
                  RadioListTile<String>(
                    title: Text(t.tagalog),
                    value: 'tl',
                    activeColor: _dark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    Widget tile({
      required IconData icon,
      required String title,
      Widget? subtitle,
      required VoidCallback onTap,
    }) => ListTile(
      leading: Icon(icon, color: _dark),
      title: Text(title),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buyerSubScreenAppBar('Account Settings'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          tile(
            icon: Icons.person_outline,
            title: 'Personal Information',
            subtitle: const Text('Name, photo and contact details'),
            onTap: () => open(const EditProfileScreen()),
          ),
          tile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            onTap: () => showChangePasswordDialog(context),
          ),
          tile(
            icon: Icons.shield_outlined,
            title: 'Privacy & Security',
            onTap: () => open(const BuyerPrivacySecurityScreen()),
          ),
          tile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () => open(const BuyerSupportScreen()),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1, color: Colors.grey[300]),
          ),

          // ---- App preferences ----
          tile(
            icon: Icons.language,
            title: AppLocalizations.of(context)!.language,
            subtitle: ListenableBuilder(
              listenable: LocaleController.instance,
              builder: (context, _) {
                final code = LocaleController.instance.languageCode;
                return Text(code == 'tl' ? 'Filipino' : 'English');
              },
            ),
            onTap: () => _showLanguagePicker(context),
          ),
          ListenableBuilder(
            listenable: ThemeController.instance,
            builder: (context, _) => SwitchListTile(
              secondary: Icon(
                ThemeController.instance.isDark
                    ? Icons.dark_mode
                    : Icons.light_mode,
                color: _dark,
              ),
              title: const Text('Dark mode'),
              value: ThemeController.instance.isDark,
              activeThumbColor: _dark,
              onChanged: (_) => ThemeController.instance.toggle(),
            ),
          ),
        ],
      ),
    );
  }
}
