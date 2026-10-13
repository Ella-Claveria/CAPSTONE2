import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'change_email_dialog.dart';
import 'change_password_dialog.dart';
import 'login_form_fields.dart';

/// Admin Portal > profile menu > Account Settings. One section for now,
/// "Security & Login": Change Email and Change Password, each opening its
/// own re-authenticating dialog.
Future<void> showAdminAccountSettingsDialog(BuildContext context) {
  final auth = AuthService();
  final email = auth.currentEmail ?? 'Not available';
  final googleOnly = !auth.hasPasswordProvider;

  return showAgriDialog<void>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      title: const Text('Account Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const Text(
            'SECURITY & LOGIN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppTheme.mid,
            ),
          ),
          const SizedBox(height: 6),
          _SettingsRow(
            icon: Icons.mail_outline_rounded,
            title: 'Change Email',
            subtitle: email,
            onTap: () => showChangeEmailDialog(dialogContext),
          ),
          const Divider(height: 1),
          _SettingsRow(
            icon: Icons.lock_outline_rounded,
            title: 'Change Password',
            subtitle: googleOnly
                ? 'Managed by your Google Account'
                : 'Requires your current password',
            onTap: () async {
              if (await showChangePasswordDialog(dialogContext)) {
                await LoginFormFields.clearSavedAdminPassword();
              }
            },
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Close',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: AppTheme.dark),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black45),
      onTap: onTap,
    );
  }
}
