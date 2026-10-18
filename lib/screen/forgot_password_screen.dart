import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audit_log_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/app_back_button.dart';
import '../widgets/email_delivery_notice.dart';
import '../widgets/email_request_leave_guard.dart';
import '../widgets/glow_field.dart';

/// Full-screen "forgot password" flow (farmer/buyer login door) — asks for
/// the account's email, requests a reset link for it so the user can
/// verify it's them and pick a new password, then shows "Check Your Email"
/// (with Resend on a cooldown) once the request has gone through.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  // Whether this was opened from the Admin login door — only that door's
  // reset requests are recorded in the Admin Portal's Audit Log (see
  // AuditLogService); farmer/buyer resets aren't in scope for it.
  //
  // With isAdmin this is not a screen of its own: it is the right-hand
  // form of the Admin sign-in page (see AdminAuthShell), which keeps the
  // photo and branding in place and swaps only this part in and out.
  final bool isAdmin;

  /// Admin only: return to the sign-in form. Called for "Back to Sign In"
  /// and the browser's Back button — after "Leave This Process?" has been
  /// answered with Leave, if a request was still being sent.
  final VoidCallback? onBack;

  /// Admin only: the narrow (single column) layout, where the page itself
  /// scrolls and this takes just the height it needs.
  final bool narrow;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.isAdmin = false,
    this.onBack,
    this.narrow = false,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _sending = false;
  bool _sent = false;
  Timer? _cooldownTimer; // counts down the resend button
  int _cooldown = 0; // seconds left before resend is allowed
  String? _resendError; // why the last resend did not go through
  String? _formError; // Admin page only: shown under the email field

  final _emailFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isAdmin) {
      // The cursor moves here from the sign-in form it was opened from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emailFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    // The mobile screen's EmailRequestLeaveGuard does this; the Admin form
    // has no guard widget around it.
    if (widget.isAdmin) _leaveConfirm.dismiss();
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // How long "Resend Reset Link" stays locked after a request. The server
  // also refuses a second email to the same address inside about a minute;
  // this keeps the button honest about it.
  static const int _resendCooldownSeconds = 60;

  // "Leave This Process?" — also decides when a finished request may
  // change this screen (see _sendResetLink).
  final _leaveConfirm = EmailLeaveConfirm();

  static final _emailFormat = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  void _startCooldown() {
    setState(() => _cooldown = _resendCooldownSeconds);
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

  // Used by both "Send Reset Link" and "Resend Reset Link". The
  // confirmation only ever appears once the request has gone through
  // without an error — and it never says whether the address has an
  // account.
  Future<void> _sendResetLink() async {
    if (_sending || _cooldown > 0) return;
    final email = _emailController.text.trim();
    // Checked before anything is sent: something@domain.tld, no spaces.
    if (!_emailFormat.hasMatch(email)) {
      _showFormError('Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _resendError = null;
      _formError = null;
    });
    final error = await AuthService().sendPasswordResetEmail(email);
    if (!mounted) return;
    // The request is done, but if "Leave This Process?" is on screen the
    // result waits for the answer: applied after Stay, dropped on Leave.
    // Until then this screen stays exactly as it was (still loading).
    _leaveConfirm.whenResolved(() => _applyResult(email, error));
  }

  // A problem with the form before the confirmation: a snackbar on mobile,
  // a line under the field on the Admin page.
  void _showFormError(String message) {
    if (widget.isAdmin) {
      setState(() => _formError = message);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // The one place a finished request changes this screen.
  void _applyResult(String email, String? error) {
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      if (_sent) {
        // Already on the confirmation: say so there, where the button is.
        setState(() => _resendError = error);
      } else {
        _showFormError(error);
      }
      return;
    }
    if (widget.isAdmin) {
      AuditLogService.logPreAuth(
        AuditAction.passwordResetRequested,
        email: email,
      );
    }
    setState(() => _sent = true);
    _startCooldown();
  }

  // ---- "Check Your Email" ----
  List<Widget> _confirmation() {
    final canResend = !_sending && _cooldown <= 0;
    return [
      // Smaller than the logo above it, so the two do not compete.
      Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 28,
            color: AppTheme.mid,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(child: Text('Check Your Email', style: AppTheme.heading(21))),
      const SizedBox(height: 8),
      Text(
        // The same words whether or not the address has an account.
        "If an account exists with this email address, you'll receive a "
        'password reset link shortly. Please check your Inbox and Spam or '
        'Junk folder.',
        textAlign: TextAlign.center,
        style: AppTheme.body(size: 13.5).copyWith(height: 1.45),
      ),
      const SizedBox(height: 18),
      const EmailDeliveryNotice(
        text:
            'The email may take a few minutes to arrive. If your account '
            'logs in with Google, use Continue with Google instead.',
      ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          // maybePop, so it asks first if a resend is still being sent.
          onPressed: () => Navigator.maybePop(context),
          style: AppTheme.primaryButton(),
          child: Text('Back to Login', style: AppTheme.buttonText()),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: canResend ? _sendResetLink : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(
              color: canResend ? AppTheme.mid : Colors.grey.shade300,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sending) ...[
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                _sending
                    ? 'Sending…'
                    : _cooldown > 0
                    ? 'Resend Reset Link in ${_cooldown}s'
                    : 'Resend Reset Link',
                style: AppTheme.body(
                  color: canResend ? AppTheme.mid : Colors.grey,
                  size: 14,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      if (_resendError != null) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _resendError!,
            style: AppTheme.body(
              color: const Color(0xFFC62828),
              size: 12.5,
            ).copyWith(height: 1.4),
          ),
        ),
      ],
    ];
  }

  // ================================================================
  // Admin Portal (web) form — a compact card for the right-hand side of
  // the Admin sign-in page. Only the layout differs from the mobile
  // screen below; the request, cooldown and leave question are the same
  // code.
  // ================================================================
  static const _adminGreen = AppTheme.dark;
  static const _adminMuted = Color(0xFF6B7468);
  static const _adminBorder = Color(0xFFDDE2DA);
  // The field and the buttons are pills, like the sign-in form's and the
  // mobile app's.
  static const double _adminControlHeight = 48;

  TextStyle _mont(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.montserrat(fontSize: size, fontWeight: weight, color: color);

  // Logo, wordmark and the "ADMIN PORTAL" label at the top of the card.
  List<Widget> _adminBrand() => [
    Center(
      child: Image.asset(
        'assets/images/logo.png',
        height: 52,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.agriculture, size: 44, color: _adminGreen),
      ),
    ),
    const SizedBox(height: 6),
    const Center(child: AgriTradeText(fontSize: 24)),
    const SizedBox(height: 4),
    Center(
      child: Text(
        'ADMIN PORTAL',
        style: _mont(
          11,
          weight: FontWeight.w700,
          color: AppTheme.mid,
        ).copyWith(letterSpacing: 2),
      ),
    ),
    const SizedBox(height: 24),
  ];

  Widget _adminError(String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: _mont(12.5, color: const Color(0xFFC62828)).copyWith(height: 1.4),
    ),
  );

  Widget _adminPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
  }) => SizedBox(
    width: double.infinity,
    height: _adminControlHeight,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _adminGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _adminGreen.withValues(alpha: 0.55),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_adminControlHeight / 2),
        ),
      ),
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label, style: _mont(14.5, weight: FontWeight.w600)),
    ),
  );

  // "Please check your Inbox and Spam or Junk folder…"
  Widget _adminReminder() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.info_outline, size: 15, color: _adminMuted),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Please check your Inbox and Spam or Junk folder. The email may '
          'take a few minutes to arrive.',
          style: _mont(12, color: _adminMuted).copyWith(height: 1.45),
        ),
      ),
    ],
  );

  List<Widget> _adminForm() => [
    Text(
      'Forgot Password?',
      style: _mont(22, weight: FontWeight.w700, color: _adminGreen),
    ),
    const SizedBox(height: 8),
    Text(
      "Enter your registered Admin email address and we'll send you a link "
      'to reset your password.',
      style: _mont(13, color: _adminMuted).copyWith(height: 1.5),
    ),
    const SizedBox(height: 22),
    Text(
      'Email Address',
      style: _mont(12.5, weight: FontWeight.w600, color: Colors.black87),
    ),
    const SizedBox(height: 8),
    SizedBox(
      height: _adminControlHeight,
      child: TextField(
        controller: _emailController,
        focusNode: _emailFocus,
        enabled: !_sending,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _sendResetLink(),
        style: _mont(14, color: Colors.black87),
        decoration: InputDecoration(
          hintText: 'Enter your admin email address',
          hintStyle: _mont(13.5, color: const Color(0xFF9AA39A)),
          prefixIcon: const Icon(
            Icons.email_outlined,
            size: 19,
            color: _adminGreen,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          border: _adminFieldBorder(_adminBorder),
          enabledBorder: _adminFieldBorder(_adminBorder),
          disabledBorder: _adminFieldBorder(_adminBorder),
          focusedBorder: _adminFieldBorder(_adminGreen, width: 1.5),
        ),
      ),
    ),
    if (_formError != null) _adminError(_formError!),
    const SizedBox(height: 18),
    _adminPrimaryButton(
      label: 'Send Reset Link',
      // Disabled while a request is out, so it cannot be sent twice.
      onPressed: _sending ? null : _sendResetLink,
      loading: _sending,
    ),
    const SizedBox(height: 16),
    _adminReminder(),
  ];

  OutlineInputBorder _adminFieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_adminControlHeight / 2),
        borderSide: BorderSide(color: color, width: width),
      );

  // After the request has gone through. Says the same thing whether or
  // not the address has an account, and never that an email was delivered.
  List<Widget> _adminConfirmation() {
    final canResend = !_sending && _cooldown <= 0;
    return [
      Text(
        'Check Your Email',
        style: _mont(22, weight: FontWeight.w700, color: _adminGreen),
      ),
      const SizedBox(height: 8),
      Text(
        "If an account exists with this email address, you'll receive a "
        'password reset link shortly.',
        style: _mont(13, color: _adminMuted).copyWith(height: 1.5),
      ),
      const SizedBox(height: 22),
      _adminPrimaryButton(
        label: 'Back to Login',
        // Asks first if a resend is still being sent.
        onPressed: _adminBack,
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: _adminControlHeight,
        child: OutlinedButton(
          onPressed: canResend ? _sendResetLink : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _adminGreen,
            side: BorderSide(color: canResend ? _adminGreen : _adminBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_adminControlHeight / 2),
            ),
          ),
          child: Text(
            _sending
                ? 'Sending…'
                : _cooldown > 0
                ? 'Resend Reset Link in ${_cooldown}s'
                : 'Resend Reset Link',
            style: _mont(14, weight: FontWeight.w600),
          ),
        ),
      ),
      if (_resendError != null) _adminError(_resendError!),
      const SizedBox(height: 16),
      _adminReminder(),
    ];
  }

  Widget _adminCard() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECEEE8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._adminBrand(),
          if (_sent) ..._adminConfirmation() else ..._adminForm(),
        ],
      ),
    ),
  );

  // Back to the sign-in form this was opened from — never anywhere else.
  // While a request is still being sent it asks "Leave This Process?"
  // first and waits for the answer; leaving does not cancel the request.
  Future<void> _adminBack() async {
    if (_sending) {
      final leave = await _leaveConfirm.show(context);
      if (!leave || !mounted) return;
    }
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.maybePop(context);
    }
  }

  Widget _adminBackLink() => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      // Arrow only; the tooltip says where it goes.
      child: IconButton(
        onPressed: _adminBack,
        tooltip: 'Back to Login',
        color: _adminGreen,
        icon: const Icon(Icons.arrow_back, size: 22),
      ),
    ),
  );

  // The form only — the photo, branding and page background belong to
  // AdminAuthShell and stay where they are.
  Widget _adminPanel() {
    final Widget content;
    if (widget.narrow) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _adminBackLink(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Center(child: _adminCard()),
          ),
        ],
      );
    } else {
      content = Column(
        children: [
          _adminBackLink(),
          Expanded(
            // minHeight = the space left, so the card sits in the vertical
            // centre until the window is too short, then scrolls.
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
                      child: _adminCard(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // The browser's Back button returns to the sign-in form too, through
    // the same question as the link above.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _adminBack();
      },
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdmin) return _adminPanel();
    // Back while a reset request is still being sent asks first.
    return EmailRequestLeaveGuard(
      processing: _sending,
      confirm: _leaveConfirm,
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Room for the floating Back button above.
                    const SizedBox(height: 4 + AppBackButton.size),
                    const SizedBox(height: 12),
                    // logo.png has a wide transparent margin around the
                    // artwork: shown larger, and only the artwork's own
                    // height is kept, so the wordmark sits right under it.
                    Align(
                      heightFactor: 0.76,
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 100,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            color: AppTheme.dark,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.agriculture,
                            size: 38,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const Center(child: AgriTradeText(fontSize: 26)),
                    const SizedBox(height: 28),
                    if (!_sent) ...[
                      const Text(
                        'Reset your password',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Enter your account email and we'll send you a link to verify it's you and reset your password.",
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.black54,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Email Address',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      GlowField(
                        controller: _emailController,
                        hint: 'you@example.com',
                        icon: Icons.email_outlined,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _sendResetLink,
                          style: AppTheme.primaryButton(),
                          child: _sending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Send Reset Link',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ] else
                      ..._confirmation(),
                  ],
                ),
              ),
              // Floats above the form so it stays put while the page scrolls.
              const Positioned(top: 8, left: 12, child: AppBackButton()),
            ],
          ),
        ),
      ),
    );
  }
}
