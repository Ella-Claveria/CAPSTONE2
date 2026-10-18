import 'dart:async';

import 'package:flutter/material.dart';

import '../services/recovery_email_service.dart';
import '../theme/app_theme.dart';
import 'agri_dialog.dart';
import 'otp_code_field.dart';

/// Verifies [email] as the account's recovery email: emails it a 6-digit
/// code, then asks for that code. True once it is verified.
///
/// The login email is refused (a recovery email is a second address). A
/// problem sending the code is shown as a message, and false returned.
Future<bool> verifyRecoveryEmail(
  BuildContext context,
  String email, {
  RecoveryEmailService? service,
}) async {
  final recovery = service ?? RecoveryEmailService();
  final messenger = ScaffoldMessenger.of(context);
  final request = await recovery.requestCode(email);
  if (request.verified) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Recovery email verified.')),
    );
    return true;
  }
  if (request.error != null || !context.mounted) {
    if (request.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(request.error!)));
    }
    return false;
  }
  final verified = await showAgriDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecoveryEmailCodeDialog(
      email: email.trim(),
      service: recovery,
      resendAfterSeconds: request.resendAfterSeconds,
    ),
  );
  if (verified == true) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Recovery email verified.')),
    );
  }
  return verified == true;
}

/// The code step: where the code went, the 6 boxes, and Resend. Pops true
/// once the code is accepted. It owns its controller, so nothing is used
/// after the popup has closed.
class RecoveryEmailCodeDialog extends StatefulWidget {
  final String email;
  final RecoveryEmailService service;
  final int resendAfterSeconds;

  const RecoveryEmailCodeDialog({
    super.key,
    required this.email,
    required this.service,
    this.resendAfterSeconds = 60,
  });

  @override
  State<RecoveryEmailCodeDialog> createState() =>
      _RecoveryEmailCodeDialogState();
}

class _RecoveryEmailCodeDialogState extends State<RecoveryEmailCodeDialog> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;
  bool _resending = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _startCooldown(widget.resendAfterSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
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

  Future<void> _verify() async {
    if (_code.text.length != OtpCodeField.length || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.service.confirmCode(_code.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    final result = await widget.service.requestCode(widget.email);
    if (!mounted) return;
    setState(() {
      _resending = false;
      _error = result.error;
    });
    if (result.verified) {
      Navigator.of(context).pop(true);
      return;
    }
    _startCooldown(result.resendAfterSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final canVerify = _code.text.length == OtpCodeField.length && !_saving;
    final canResend = _cooldown <= 0 && !_resending && !_saving;
    final resendLabel = _resending
        ? 'Sending code…'
        : _cooldown > 0
        ? 'Resend code in ${_cooldown}s'
        : 'Resend code';
    return AgriDialog(
      icon: Icons.mark_email_unread_outlined,
      title: const Text('Verify Recovery Email'),
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
                widget.email,
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
            focusNode: _focus,
            enabled: !_saving,
            onSubmitted: (_) => _verify(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'The code expires in 10 minutes. Not in your inbox? Check your '
            'Spam or Junk folder.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: canResend ? _resend : null,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(resendLabel),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.dark,
                disabledForegroundColor: Colors.grey.shade500,
                textStyle: AppTheme.label().copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AgriDialogButton(
          label: 'Verify',
          kind: AgriButtonKind.primary,
          loading: _saving,
          onPressed: canVerify ? _verify : null,
        ),
      ],
    );
  }
}

/// "Verified" (green) or "Not verified" (orange), beside a recovery email.
class RecoveryEmailStatusChip extends StatelessWidget {
  final bool verified;

  const RecoveryEmailStatusChip({super.key, required this.verified});

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppTheme.mid : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: verified ? AppTheme.accent : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.error_outline_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'Verified' : 'Not verified',
            style: AppTheme.label().copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
