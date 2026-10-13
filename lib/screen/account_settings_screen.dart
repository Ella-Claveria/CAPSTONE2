import '../widgets/agri_app_bar.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/change_password_dialog.dart';
import 'farmer_edit_profile_screen.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  static const Color _dark = AppTheme.dark;

  void _showLanguagePicker(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final currentCode = LocaleController.instance.languageCode;
    showAgriSheet<void>(
      context: context,
      title: t.selectLanguage,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<String>(
            groupValue: currentCode,
            onChanged: (value) {
              if (value == null) return;
              LocaleController.instance.setLocale(Locale(value));
              Navigator.pop(sheetContext);
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
      ),
    );
  }

  // Also opened straight from the Manage Account screen.
  static void showHelp(BuildContext context) {
    showAgriDialog<void>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.help_outline,
        title: const Text('Help & Support'),
        content: const Text(
          'For help with orders, profiles, or account access, contact AgriTrade+ support.',
        ),
        actions: [
          AgriDialogButton(
            label: 'Close',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AgriAppBar(title: 'Account Settings'),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language, color: _dark),
            title: Text(AppLocalizations.of(context)!.language),
            subtitle: ListenableBuilder(
              listenable: LocaleController.instance,
              builder: (context, _) => Text(
                LocaleController.instance.isTagalog ? 'Filipino' : 'English',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: _dark),
            title: const Text('Change password'),
            onTap: () => showChangePasswordDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined, color: _dark),
            title: const Text('Recovery email'),
            subtitle: const Text('Add or verify it in your profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
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
          ListTile(
            leading: const Icon(Icons.help_outline, color: _dark),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showHelp(context),
          ),
        ],
      ),
    );
  }
}
