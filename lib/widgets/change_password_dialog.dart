import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/password_change_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'agri_form_field.dart';
import 'otp_code_field.dart';
import 'password_requirements.dart';

/// Shared "change password" flow for logged-in farmers, buyers, and
/// admins, in two steps:
///
///  1. the current password and the new one (with the registration rules
///     shown live) — Continue checks the current password and emails a
///     6-digit code to the account's own email;
///  2. that code — Change Password changes it, signs the account out on
///     every other device and emails a notice; this device stays signed in.
///
/// Resolves to whether the password was actually changed.
Future<bool> showChangePasswordDialog(
  BuildContext context, {
  PasswordChangeService? service,
}) async {
  // A Google-only account has no password to re-authenticate with or
  // change — say so instead of failing on "current password".
  if (service == null && !AuthService().hasPasswordProvider) {
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

  final changed = await showAgriDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        ChangePasswordDialog(service: service ?? PasswordChangeService()),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password changed. Other devices were logged out.'),
      ),
    );
  }
  return changed == true;
}

/// The Change Password popup. It owns its fields, so nothing is used after
/// it has closed.
class ChangePasswordDialog extends StatefulWidget {
  final PasswordChangeService service;

  const ChangePasswordDialog({super.key, required this.service});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _busy = false;
  bool _codeStep = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  String get _email => widget.service.email;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    if (seconds <= 0) return;
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  // Step 1 → 2: check the current password and email the code.
  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.requestCode(
      currentPassword: _current.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      if (result.error == null) _codeStep = true;
    });
    _startCooldown(result.resendAfterSeconds);
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.requestCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });
    _startCooldown(result.resendAfterSeconds);
  }

  Future<void> _change() async {
    if (_code.text.length != OtpCodeField.length || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.service.confirm(
      code: _code.text,
      newPassword: _new.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) =>
      _codeStep ? _codeDialog() : _formDialog();

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      _error!,
      textAlign: TextAlign.center,
      style: AppTheme.body(size: 12, color: Colors.red.shade700),
    ),
  );

  Widget _formDialog() {
    return AgriDialog(
      title: const Text('Change Password'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            AgriFormField(
              label: 'Current password',
              controller: _current,
              hint: 'Enter your current password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Required' : null,
            ),
            AgriFormField(
              label: 'New password',
              controller: _new,
              hint: 'Enter a new password',
              icon: Icons.lock_reset_rounded,
              obscureText: _obscure,
              // The registration rules, shown live below.
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) return 'Required';
                if (!PasswordRules.meetsAll(password)) {
                  return 'Password must meet all the requirements below.';
                }
                if (password == _current.text) {
                  return 'Choose a password different from your current one.';
                }
                return null;
              },
            ),
            // Hidden until a new password is typed, then each rule turns
            // green as it is met — as in registration.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _new,
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
              controller: _confirm,
              hint: 'Enter the new password again',
              icon: Icons.lock_reset_rounded,
              obscureText: _obscure,
              validator: (value) =>
                  value != _new.text ? 'Passwords do not match.' : null,
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _obscure = !_obscure),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: !_obscure,
                        activeColor: AppTheme.dark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        onChanged: (checked) =>
                            setState(() => _obscure = !(checked ?? false)),
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
            const SizedBox(height: 6),
            Text(
              'We will email a 6-digit code to your login email to confirm '
              'it is you.',
              style: AppTheme.body(size: 12, color: Colors.grey.shade600),
            ),
            if (_error != null) _errorText(),
          ],
        ),
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        AgriDialogButton(
          label: 'Continue',
          kind: AgriButtonKind.primary,
          loading: _busy,
          onPressed: _busy ? null : _continue,
        ),
      ],
    );
  }

  Widget _codeDialog() {
    final canChange = _code.text.length == OtpCodeField.length && !_busy;
    final canResend = _cooldown <= 0 && !_busy;
    return AgriDialog(
      icon: Icons.mark_email_unread_outlined,
      title: const Text('Confirm Password Change'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the 6-digit code we sent to',
            style: AppTheme.body(size: 13.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.label().copyWith(
                  color: AppTheme.dark,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          OtpCodeField(
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy,
            onSubmitted: (_) => _change(),
          ),
          if (_error != null) _errorText(),
          const SizedBox(height: 12),
          Text(
            'Changing it logs you out on every other device.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 11.5, color: Colors.grey.shade600),
          ),
          Center(
            child: TextButton.icon(
              onPressed: canResend ? _resend : null,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                _cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.dark,
                disabledForegroundColor: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Back',
          onPressed: _busy
              ? null
              : () => setState(() {
                  _codeStep = false;
                  _error = null;
                  _code.clear();
                }),
        ),
        AgriDialogButton(
          label: 'Change Password',
          kind: AgriButtonKind.primary,
          loading: _busy,
          onPressed: canChange ? _change : null,
        ),
      ],
    );
  }
}
