import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Shared "change password" flow for logged-in farmers, buyers, and
/// admins. Requires the current password (Firebase needs a recent
/// sign-in for this kind of sensitive change, so this doubles as that).
Future<void> showChangePasswordDialog(BuildContext context) async {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool saving = false;
  bool obscure = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Change password'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: currentController,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'Current password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newController,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'At least 6 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscure,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value != newController.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                    CheckboxListTile(
                      value: !obscure,
                      onChanged: (checked) => setState(() => obscure = !(checked ?? false)),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Show passwords', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        setState(() => saving = true);
                        final error = await AuthService().updatePassword(
                          currentPassword: currentController.text,
                          newPassword: newController.text,
                        );
                        if (!dialogContext.mounted) return;
                        if (error != null) {
                          setState(() => saving = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error)),
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password updated.')),
                        );
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  currentController.dispose();
  newController.dispose();
  confirmController.dispose();
}
