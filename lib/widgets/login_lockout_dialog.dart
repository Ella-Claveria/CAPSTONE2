import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'agri_dialog.dart';

/// "Too Many Login Attempts": shown when password login for an email is
/// paused after repeated wrong passwords (see AuthService.logIn and
/// functions/login_throttle.js).
///
/// [waitSeconds] is how long the pause still has to run, as reported by
/// the server; the dialog counts it down. Pass null when the wait is not
/// known — Firebase Authentication's own rate limit does not say how long
/// it lasts — and no countdown is shown.
///
/// [onForgotPassword] opens the password-reset flow, which stays available
/// during the pause.
Future<void> showLoginLockoutDialog(
  BuildContext context, {
  required int? waitSeconds,
  required VoidCallback onForgotPassword,
}) {
  return showAgriDialog<void>(
    context: context,
    // Follows the system font size up to 130%, so the dialog stays compact
    // with its buttons in view; beyond that it scrolls rather than grows.
    builder: (dialogContext) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _LoginLockoutDialog(
        waitSeconds: waitSeconds,
        onForgotPassword: () {
          Navigator.of(dialogContext).pop();
          onForgotPassword();
        },
      ),
    ),
  );
}

class _LoginLockoutDialog extends StatefulWidget {
  final int? waitSeconds;
  final VoidCallback onForgotPassword;

  const _LoginLockoutDialog({
    required this.waitSeconds,
    required this.onForgotPassword,
  });

  @override
  State<_LoginLockoutDialog> createState() => _LoginLockoutDialogState();
}

class _LoginLockoutDialogState extends State<_LoginLockoutDialog> {
  // Counted from a fixed end time, so it stays right if a tick is late.
  DateTime? _endsAt;
  Timer? _ticker;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    final wait = widget.waitSeconds;
    if (wait != null && wait > 0) {
      _endsAt = DateTime.now().add(Duration(seconds: wait));
      _remaining = wait;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    final left = _endsAt!.difference(DateTime.now()).inMilliseconds;
    final seconds = left <= 0 ? 0 : (left / 1000).ceil();
    if (seconds == 0) _ticker?.cancel();
    if (mounted) setState(() => _remaining = seconds);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static const double _radius = 22;
  static const double _buttonHeight = 46;
  static const Color _warning = Color(0xFFEF6C00);

  // Both buttons share this: same height, same pill shape, and a label
  // that shrinks rather than wraps, so they stay identical whatever the
  // screen width or the system font size.
  Widget _button({
    required String label,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_buttonHeight / 2),
    );
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return Expanded(
      child: SizedBox(
        height: _buttonHeight,
        child: filled
            ? ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: padding,
                  shape: shape,
                ),
                child: child,
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.mid,
                  side: const BorderSide(color: AppTheme.mid, width: 1.2),
                  padding: padding,
                  shape: shape,
                ),
                child: child,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timed = _endsAt != null;
    final finished = timed && _remaining == 0;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        // Scrolls instead of overflowing on a short screen or with a large
        // system font.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_outlined,
                  color: _warning,
                  size: 27,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Too Many Login Attempts',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.dark,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  timed
                      ? "You've entered an incorrect password multiple times. "
                            'Please wait 5 minutes before trying again, or '
                            'reset your password.'
                      : "You've entered an incorrect password multiple times. "
                            'Please wait a few minutes before trying again, '
                            'or reset your password.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (timed) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        finished ? 'You can try again now' : 'Try again in',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: finished ? 13.5 : 12,
                          fontWeight: finished
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: finished ? AppTheme.dark : Colors.black54,
                        ),
                      ),
                      if (!finished) ...[
                        const SizedBox(height: 4),
                        Text(
                          _clock(_remaining),
                          style: GoogleFonts.montserrat(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.dark,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _button(
                    label: 'Reset Password',
                    filled: false,
                    onPressed: widget.onForgotPassword,
                  ),
                  const SizedBox(width: 10),
                  _button(
                    label: finished ? 'Try Again' : 'OK',
                    filled: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
