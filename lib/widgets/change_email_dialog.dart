import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/admin_session_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'agri_form_field.dart';
import 'email_request_leave_guard.dart';
import 'otp_code_field.dart';

/// "Change email" flow for a logged-in Admin with a password account
/// (Admin Portal > Manage Account). First the new email and the current
/// password; once the system accepts the new email it is sent a 6-digit
/// code, and the sign-in email changes only when that code is entered (see
/// [AuthService.requestEmailChangeCode]). Changing it ends the account's
/// sessions, so the Admin is then logged out to log in with the new email.
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

  final changedTo = await showAgriDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangeEmailDialog(currentEmail: auth.currentEmail ?? ''),
  );
  if (changedTo == null || !context.mounted) return;

  await _showNotice(
    context,
    icon: Icons.mark_email_read_outlined,
    title: 'Email changed',
    message:
        'Your email is now $changedTo.\n\nYou will be logged out. Please '
        'log in again using your new email.',
  );

  // Firebase has already ended the account's sessions; leave cleanly now
  // instead of failing on the next token refresh. Ending this browser's
  // Admin session is best-effort, as on Logout.
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    try {
      await AdminSessionService.end(uid).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
  await FirebaseAuth.instance.signOut();
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
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  late final _currentEmailController = TextEditingController(
    text: widget.currentEmail,
  );
  late final _newController = TextEditingController()
    ..addListener(() => setState(() {}));
  final _passwordController = TextEditingController();
  late final _codeController = TextEditingController()
    ..addListener(() => setState(() {}));
  late final _codeFocus = FocusNode()..addListener(() => setState(() {}));

  bool _saving = false;
  bool _obscure = true;
  bool _triedSubmit = false;
  String? _error;

  // Set once the new email has been accepted and sent its code: the
  // dialog then asks for that code.
  String? _sentTo;
  bool _resending = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  // The registration form's email rule (Gmail only) with the municipal
  // office's own domain also accepted, since this is an Admin's email.
  static final _emailPattern = RegExp(
    r'^[\w\.\-]+@(gmail\.com|laurelbatangas\.gov\.ph)$',
    caseSensitive: false,
  );

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _leaveConfirm.dismiss();
    _currentEmailController.dispose();
    _newController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // As in registration: checked while typing, with the same message; an
  // empty field is only an error once the form has been submitted.
  String? _newEmailError(String value) {
    final email = value.trim();
    if (email.isEmpty) return _triedSubmit ? 'Required' : null;
    if (!_emailPattern.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }
    if (email.toLowerCase() == widget.currentEmail.trim().toLowerCase()) {
      return 'That is already your current email.';
    }
    return null;
  }

  // The server enforces the wait; this only keeps the button honest.
  void _startCooldown(int seconds) {
    if (seconds <= 0) return;
    setState(() => _cooldown = seconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  // Step 1: check the password, then have the new email sent a code.
  Future<void> _sendCode() async {
    setState(() => _triedSubmit = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final newEmail = _newController.text.trim();
    final result = await _auth.requestEmailChangeCode(
      newEmail: newEmail,
      currentPassword: _passwordController.text,
    );
    if (!mounted) return;
    // If "Leave This Process?" is on screen, the result waits for the
    // answer (applied after Stay, dropped on Leave) — changing this dialog
    // now would change it behind the question.
    _leaveConfirm.whenResolved(() {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (result.error != null) {
          _error = result.error;
        } else {
          _sentTo = newEmail;
          _codeController.clear();
        }
      });
      _startCooldown(result.resendAfterSeconds);
    });
  }

  Future<void> _resend() async {
    final sentTo = _sentTo;
    if (sentTo == null || _resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final result = await _auth.requestEmailChangeCode(newEmail: sentTo);
    if (!mounted) return;
    setState(() {
      _resending = false;
      _error = result.error;
      // The previous code no longer works — don't leave it typed in.
      if (result.error == null) _codeController.clear();
    });
    _startCooldown(result.resendAfterSeconds);
    if (result.error == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Verification code sent')));
    }
  }

  // Step 2: the code; when it is right the email is changed.
  Future<void> _verify() async {
    final code = _codeController.text;
    if (code.length != OtpCodeField.length || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await _auth.confirmEmailChangeCode(code);
    if (!mounted) return;
    _leaveConfirm.whenResolved(() {
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _saving = false;
          _error = error;
        });
        return;
      }
      Navigator.of(context).pop(_sentTo);
    });
  }

  // Back from the code to the form, to correct the new email.
  void _editEmail() {
    setState(() {
      _sentTo = null;
      _error = null;
      _codeController.clear();
    });
  }

  final _leaveConfirm = EmailLeaveConfirm();

  @override
  Widget build(BuildContext context) {
    // Back/Escape while a request is still being sent asks first.
    return EmailRequestLeaveGuard(
      processing: _saving,
      confirm: _leaveConfirm,
      child: _sentTo == null ? _formDialog(context) : _codeDialog(context),
    );
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      _error!,
      style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
    ),
  );

  Widget _formDialog(BuildContext context) {
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
              caption: 'A verification code will be sent to this email.',
              autovalidateMode: AutovalidateMode.always,
              validator: (value) => _newEmailError(value ?? ''),
            ),
            AgriFormField(
              label: 'Current password',
              controller: _passwordController,
              hint: 'Enter your current password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              caption: 'Needed to confirm it is you.',
              onSubmitted: (_) => _saving ? null : _sendCode(),
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
            if (_error != null) _errorText(),
          ],
        ),
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AgriDialogButton(
          label: 'Send Code',
          kind: AgriButtonKind.primary,
          loading: _saving,
          onPressed: _saving ? null : _sendCode,
        ),
      ],
    );
  }

  Widget _codeDialog(BuildContext context) {
    final canVerify =
        _codeController.text.length == OtpCodeField.length && !_saving;
    final canResend = _cooldown <= 0 && !_resending && !_saving;
    return AgriDialog(
      icon: Icons.mark_email_unread_outlined,
      title: const Text('Verify New Email'),
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
          // The new email, in a pill so it reads as "where the code went".
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.alternate_email_rounded,
                    size: 16,
                    color: AppTheme.dark,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _sentTo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.label().copyWith(
                        color: AppTheme.dark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          OtpCodeField(
            controller: _codeController,
            focusNode: _codeFocus,
            enabled: !_saving,
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Center(child: _errorText()),
          ],
          const SizedBox(height: 16),
          _codeNote(),
          const SizedBox(height: 12),
          _codeLinks(canResend),
        ],
      ),
      actions: [
        SizedBox(
          width: 128,
          child: AgriDialogButton(
            label: 'Cancel',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
        SizedBox(
          width: 128,
          child: AgriDialogButton(
            label: 'Verify',
            kind: AgriButtonKind.primary,
            loading: _saving,
            onPressed: canVerify ? _verify : null,
          ),
        ),
      ],
    );
  }

  // How long the code lasts and where else to look for it, in a soft box.
  Widget _codeNote() {
    final style = AppTheme.body(size: 12, color: Colors.grey.shade700);
    Widget line(IconData icon, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: AppTheme.mid),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: style, textAlign: TextAlign.start),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E8E1)),
      ),
      child: Column(
        children: [
          line(Icons.schedule_rounded, 'The code expires in 10 minutes.'),
          const SizedBox(height: 6),
          line(
            Icons.inbox_outlined,
            'Not in your inbox? Check your Spam or Junk folder.',
          ),
        ],
      ),
    );
  }

  // Resend (with its countdown) and going back to fix the email, as one
  // row of links split by a thin divider.
  Widget _codeLinks(bool canResend) {
    final resendLabel = _resending
        ? 'Sending code…'
        : _cooldown > 0
        ? 'Resend code in ${_cooldown}s'
        : 'Resend code';
    Widget link(IconData icon, String label, VoidCallback? onTap) =>
        TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.dark,
            disabledForegroundColor: Colors.grey.shade500,
            textStyle: AppTheme.label().copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        link(Icons.refresh_rounded, resendLabel, canResend ? _resend : null),
        Container(width: 1, height: 16, color: Colors.grey.shade300),
        link(Icons.edit_outlined, 'Change email', _saving ? null : _editEmail),
      ],
    );
  }
}
