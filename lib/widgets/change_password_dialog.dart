import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'agri_dialog.dart';
import '../theme/app_theme.dart';
import 'agri_form_field.dart';
import 'password_requirements.dart';

/// Shared "change password" flow for logged-in farmers, buyers, and
/// admins. Requires the current password (Firebase needs a recent
/// sign-in for this kind of sensitive change, so this doubles as that).
/// Resolves to whether the password was actually changed.
Future<bool> showChangePasswordDialog(BuildContext context) async {
  // A Google-only account has no password to re-authenticate with or
  // change — say so instead of failing on "current password".
  if (!AuthService().hasPasswordProvider) {
    await showAgriDialog<void>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.lock_outline,
        title: const Text('Change Password'),
        content: const Text(
          'This account logs in with Google, so it has no AgriTrade+ '
          'password to change. Manage your password in your Google Account.',
        ),
        actions: [
          AgriDialogButton(
            label: 'OK',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    return false;
  }

  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool saving = false;
  bool obscure = true;
  bool changed = false;

  try {
    await showAgriDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AgriDialog(
              title: const Text('Change Password'),
              scrollable: true,
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      AgriFormField(
                        label: 'Current password',
                        controller: currentController,
                        hint: 'Enter your current password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: obscure,
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      AgriFormField(
                        label: 'New password',
                        controller: newController,
                        hint: 'Enter a new password',
                        icon: Icons.lock_reset_rounded,
                        obscureText: obscure,
                        // The registration rules, shown live below.
                        validator: (value) {
                          final password = value ?? '';
                          if (password.isEmpty) return 'Required';
                          if (!PasswordRules.meetsAll(password)) {
                            return 'Password must meet all the requirements '
                                'below.';
                          }
                          if (password == currentController.text) {
                            return 'Choose a password different from your '
                                'current one.';
                          }
                          return null;
                        },
                      ),
                      // Hidden until a new password is typed, then each rule
                      // turns green as it is met — as in registration.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: newController,
                        builder: (_, value, _) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: PasswordRequirementsChecklist(
                            password: value.text,
                            bottomSpacing: value.text.isEmpty ? 0 : 14,
                          ),
                        ),
                      ),
                      AgriFormField(
                        label: 'Confirm new password',
                        controller: confirmController,
                        hint: 'Enter the new password again',
                        icon: Icons.lock_reset_rounded,
                        obscureText: obscure,
                        validator: (value) {
                          if (value != newController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      // A plain row, not a list tile: nothing behind it, so
                      // it sits on the popup like the fields above.
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => obscure = !obscure),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: !obscure,
                                  activeColor: AppTheme.dark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  onChanged: (checked) => setState(
                                    () => obscure = !(checked ?? false),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Show passwords',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                AgriDialogButton(
                  label: 'Cancel',
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                ),
                AgriDialogButton(
                  label: 'Save Changes',
                  kind: AgriButtonKind.primary,
                  loading: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setState(() => saving = true);
                          final error = await AuthService().updatePassword(
                            currentPassword: currentController.text,
                            newPassword: newController.text,
                          );
                          if (!dialogContext.mounted) return;
                          if (error != null) {
                            setState(() => saving = false);
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(SnackBar(content: Text(error)));
                            return;
                          }
                          changed = true;
                          Navigator.of(dialogContext).pop();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password updated successfully.'),
                            ),
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }
  return changed;
}
