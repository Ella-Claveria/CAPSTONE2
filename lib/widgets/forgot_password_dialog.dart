import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Shared "forgot password" flow for the farmer, buyer, and admin login
/// screens — collects an email, sends a Firebase reset link, and reports
/// back with a snackbar. Same behavior everywhere since all three roles
/// are just Firebase Auth users underneath.
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) async {
  final controller = TextEditingController(text: initialEmail);
  final formKey = GlobalKey<FormState>();
  bool sending = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Reset your password'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Enter your account email and we'll send you a link to reset your password.",
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty || !trimmed.contains('@')) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        setState(() => sending = true);
                        final error = await AuthService()
                            .sendPasswordResetEmail(controller.text.trim());
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error ??
                                  'Password reset link sent — check your inbox.',
                            ),
                          ),
                        );
                      },
                child: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Link'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
}
