import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'agri_dialog.dart';
import 'agri_form_field.dart';
import 'email_request_leave_guard.dart';

/// "Change email" flow for a logged-in password account (Admin Portal >
/// Account Settings > Security & Login). Asks for the current password to
/// re-authenticate, then Firebase emails a confirmation link to the new
/// address — the sign-in email changes only once that link is opened (see
/// [AuthService.requestEmailChange]).
Future<void> showChangeEmailDialog(BuildContext context) async {
  final auth = AuthService();
  // A Google-only account's email belongs to Google — nothing to change
  // here, and no password to re-authenticate with.
  if (!auth.hasPasswordProvider) {
    await _showNotice(
      context,
      icon: Icons.mail_outline_rounded,
      title: 'Change Email',
      message:
          'This account logs in with Google, so its email is managed by '
          'your Google Account and cannot be changed here.',
    );
    return;
  }

  final sentTo = await showAgriDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangeEmailDialog(currentEmail: auth.currentEmail ?? ''),
  );
  if (sentTo == null || !context.mounted) return;

  await _showNotice(
    context,
    icon: Icons.mark_email_read_outlined,
    title: 'Confirm your new email',
    message:
        'We sent a confirmation link to $sentTo. Open it to finish the '
        'change.\n\nUntil then you keep logging in with your current email. '
        'Once confirmed, you will be signed out and can log in with the '
        'new one.',
  );
}

Future<void> _showNotice(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
}) {
  return showAgriDialog<void>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: icon,
      title: Text(title),
      content: Text(message),
      actions: [
        AgriDialogButton(
          label: 'OK',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

class _ChangeEmailDialog extends StatefulWidget {
  final String currentEmail;
  const _ChangeEmailDialog({required this.currentEmail});

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _currentEmailController = TextEditingController(
    text: widget.currentEmail,
  );
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _currentEmailController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final newEmail = _newController.text.trim();
    final error = await AuthService().requestEmailChange(
      currentPassword: _passwordController.text,
      newEmail: newEmail,
    );
    if (!mounted) return;
    // If "Leave This Process?" is on screen, the result waits for the
    // answer (applied after Stay, dropped on Leave) — closing this dialog
    // now would close the question instead.
    _leaveConfirm.whenResolved(() {
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _saving = false;
          _error = error;
        });
        return;
      }
      Navigator.of(context).pop(newEmail);
    });
  }

  final _leaveConfirm = EmailLeaveConfirm();

  @override
  Widget build(BuildContext context) {
    // Back/Escape while the request is still being sent asks first.
    return EmailRequestLeaveGuard(
      processing: _saving,
      confirm: _leaveConfirm,
      child: _dialog(context),
    );
  }

  Widget _dialog(BuildContext context) {
    return AgriDialog(
      title: const Text('Change Email'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            AgriFormField(
              label: 'Current email',
              controller: _currentEmailController,
              hint: 'Your current email',
              icon: Icons.mail_outline_rounded,
              readOnly: true,
            ),
            AgriFormField(
              label: 'New email',
              controller: _newController,
              hint: 'Enter your new email',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              caption: 'A confirmation link will be sent to this email.',
              validator: (value) {
                final email = (value ?? '').trim();
                if (!_emailPattern.hasMatch(email)) {
                  return 'Enter a valid email address.';
                }
                if (email.toLowerCase() ==
                    widget.currentEmail.trim().toLowerCase()) {
                  return 'That is already your current email.';
                }
                return null;
              },
            ),
            AgriFormField(
              label: 'Confirm new email',
              controller: _confirmController,
              hint: 'Enter your new email again',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (value) =>
                  (value ?? '').trim().toLowerCase() ==
                      _newController.text.trim().toLowerCase()
                  ? null
                  : 'Emails do not match.',
            ),
            AgriFormField(
              label: 'Current password',
              controller: _passwordController,
              hint: 'Enter your current password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              caption: 'Needed to confirm it is you.',
              onSubmitted: (_) => _saving ? null : _submit(),
              suffix: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Required' : null,
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AgriDialogButton(
          label: 'Save Changes',
          kind: AgriButtonKind.primary,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
