// ============================================================
// email_verification_screen.dart
// ------------------------------------------------------------
// COVERS: Objective 4.2 — "Requiring mandatory account
// verification via email for all registered users."
//
// HOW IT WORKS:
// After signing up, a 6-digit code is emailed to the user's
// address. The code is generated, stored (hashed) and checked by
// Cloud Functions (functions/email_otp.js) — this screen only
// asks for one, collects what the user types and sends it to be
// checked. Until a correct code is entered the account stays
// "unverified" and every login is routed back here (see
// AuthRoutingService).
//
// Once verified, the full profile collected at registration
// (name, barangay, certificate, etc. — see PendingRegistrationProfile)
// is written to Firestore for the first time here, never before —
// see AuthService.completeRegistration's doc comment for why.
// ============================================================

import '../widgets/agri_app_bar.dart';
import '../widgets/email_delivery_notice.dart';
import '../widgets/email_request_leave_guard.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/email_mask.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'login_screen.dart';
import 'page_transitions.dart';
import 'pending_approval_screen.dart';
import 'register_screen.dart';
import 'role_selection_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String role; // 'farmer' or 'buyer'
  final String email; // shown masked, so they know where to look
  // Everything collected on the registration form that still needs to be
  // written to Firestore once verification succeeds (see
  // AuthService.completeRegistration). Null when resuming an existing
  // unverified session from a fresh app launch — _finishVerified falls
  // back to AuthService.loadPendingProfile in that case, since this
  // constructor argument doesn't survive the app being closed.
  final PendingRegistrationProfile? pendingProfile;

  const EmailVerificationScreen({
    super.key,
    required this.role,
    required this.email,
    this.pendingProfile,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _codeLength = 6;

  final _authService = AuthService();
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  Timer? _cooldownTimer; // counts down the resend button
  int _cooldown = 0; // seconds left before resend is allowed
  bool _requesting = false;
  bool _verifying = false;
  bool _navigatingAway = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _codeFocus.addListener(_onCodeChanged);

    // Ask for a code once, when the screen opens. Whether an email actually
    // goes out is the server's call: it sends only if there is no code this
    // account could still use, so opening this screen again (a rebuild, a
    // hot restart, reopening the app) never sends a duplicate.
    _requestCode(resend: false);
  }

  @override
  void dispose() {
    // Very important: stop the timer when leaving this screen,
    // or it keeps running in the background and causes errors.
    _cooldownTimer?.cancel();
    _leaveConfirm.dismiss();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------
  // Ask for a code (or, with resend, a new one that replaces it).
  // ----------------------------------------------------------
  Future<void> _requestCode({required bool resend}) async {
    if (_requesting || _navigatingAway) return;
    setState(() => _requesting = true);

    final result = await _authService.requestEmailOtp(resend: resend);
    if (!mounted) return;
    // If "Leave This Process?" is on screen, the result waits for the
    // answer: applied after Stay, dropped on Leave. Nothing here changes
    // or navigates while the question is open.
    _leaveConfirm.whenResolved(() => _applyCodeRequest(result, resend));
  }

  Future<void> _applyCodeRequest(
    EmailOtpRequestResult result,
    bool resend,
  ) async {
    if (!mounted || _navigatingAway) return;
    setState(() => _requesting = false);

    if (result.alreadyVerified) {
      await _finishVerified();
      return;
    }
    if (result.resendAfterSeconds > 0) {
      _startCooldown(result.resendAfterSeconds);
    }
    if (result.error != null) {
      _showMessage(result.error!);
      return;
    }
    if (result.sent) {
      // The previous code (if any) no longer works — don't leave it typed in.
      if (resend) _codeController.clear();
      _showMessage('Verification code sent', isError: false);
    }
  }

  // The server enforces the wait; this only keeps the button honest about it.
  void _startCooldown(int seconds) {
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

  // ----------------------------------------------------------
  // Send the typed code to be checked.
  // ----------------------------------------------------------
  Future<void> _verify() async {
    final code = _codeController.text;
    if (code.length != _codeLength || _verifying || _navigatingAway) return;
    setState(() => _verifying = true);

    try {
      final error = await _authService.verifyEmailOtp(code);
      if (!mounted) return;
      if (error != null) {
        _codeController.clear();
        _showMessage(error);
        return;
      }
      await _finishVerified();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // ----------------------------------------------------------
  // The server has marked this email verified: pick that up in this
  // session, write the profile, and continue to the account's flow.
  // ----------------------------------------------------------
  Future<void> _finishVerified() async {
    if (_navigatingAway) return;
    _navigatingAway = true;

    try {
      final verificationError = await _authService.refreshVerifiedEmailToken();
      if (!mounted) return;
      if (verificationError != null) {
        _navigatingAway = false;
        _showMessage(verificationError);
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final profile = uid == null
          ? null
          : (widget.pendingProfile ??
                await _authService.loadPendingProfile(uid));
      final resolvedRole = profile?.role ?? widget.role;
      final profileError = await _completeRegistrationIfNeeded(
        uid,
        profile,
        resolvedRole,
      );
      if (!mounted) return;
      if (profileError != null) {
        _navigatingAway = false;
        _showMessage(profileError);
        return;
      }

      if (resolvedRole == 'farmer') {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const PendingApprovalScreen(justVerified: true),
          ),
          (route) => false,
        );
      } else {
        await _backToLogin();
      }
    } catch (_) {
      if (mounted) {
        _navigatingAway = false;
        _showMessage('Could not finish verification. Please try again.');
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  // Writes the full Firestore profile for the very first time — see
  // AuthService.completeRegistration's doc comment. Skipped (not an
  // error) if a doc already exists for this uid, which covers both "this
  // already ran once" and a legacy account that was fully registered
  // before this deferred-write design existed (the server stamps
  // emailOtpVerified on an existing doc itself).
  Future<String?> _completeRegistrationIfNeeded(
    String? uid,
    PendingRegistrationProfile? profile,
    String role,
  ) async {
    if (uid == null) return null;

    final existing = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (existing.exists) return null;

    final error = await _authService.completeRegistration(
      uid: uid,
      fullName: profile?.fullName.trim().isNotEmpty == true
          ? profile!.fullName
          : (FirebaseAuth.instance.currentUser?.displayName ??
                widget.email.split('@').first),
      email: widget.email,
      role: role,
      mobileNumber: profile?.mobileNumber,
      supportedProductsAcknowledged:
          profile?.supportedProductsAcknowledged ?? false,
      barangay: profile?.barangay,
      certificateUrl: profile?.certificateUrl,
      rsbaNumber: profile?.rsbaNumber,
      emailOtpVerified: true,
    );
    if (error == null) await _authService.clearPendingProfile(uid);
    return error;
  }

  // ----------------------------------------------------------
  // Verifying an email signs the account out again and sends them back to
  // the login screen — the account isn't considered "logged in" for real
  // until they actually enter their password again afterward. This is a
  // deliberate security step, not a bug: it stops anyone who got hold of
  // the (still-open) sign-up session on this device from riding it straight
  // into the app just because the code was entered.
  // ----------------------------------------------------------
  Future<void> _backToLogin() async {
    try {
      await _authService.signOut();
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          role: widget.role,
          flashMessage: 'Email verified! Please log in to continue.',
          // The only route left: its back arrow would pop to nothing.
          disableBackNavigation: true,
        ),
      ),
      (route) => false, // clears the back stack
    );
  }

  // ----------------------------------------------------------
  // Leaving without verifying. Neither way out touches the account itself:
  // logging in with it again, still unverified, comes straight back here
  // (see AuthRoutingService).
  //
  // This screen is reached either via pushReplacement (fresh registration,
  // other screens still underneath) or pushAndRemoveUntil (a resumed
  // unverified session, nothing underneath), so nothing here pops or
  // relies on what's below: both clear the stack and build the one they
  // need.
  // ----------------------------------------------------------
  // The app's login screen for this platform — the same entry point
  // auth_route_handler returns a blocked session to. On mobile that is the
  // front door (RoleSelectionScreen: the role-agnostic login form, with no
  // back arrow of its own). A bare LoginScreen must never be left as the
  // only route here: its back arrow pops, and popping the last route
  // leaves a black screen.
  Widget _loginDoor() =>
      kIsWeb ? const LoginScreen(role: 'admin') : const RoleSelectionScreen();

  // Back (the arrow or the system back button): to Login, staying signed
  // in. The stack is cleared, so Login is the one and only route.
  // Back (the arrow and the system back button). While a code request is
  // still being sent it asks "Leave This Process?" first; otherwise it
  // goes straight back to the login door, as before.
  final _leaveConfirm = EmailLeaveConfirm();

  Future<void> _onBack() async {
    if (_requesting) {
      final leave = await _leaveConfirm.show(context);
      if (!leave || !mounted) return;
    }
    _backToLoginDoor();
  }

  void _backToLoginDoor() {
    if (_navigatingAway) return;
    _navigatingAway = true;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _loginDoor()),
      (route) => false,
    );
  }

  // "Use a different account": sign this unverified session out, then open
  // Sign Up. The stack is rebuilt as Login -> Sign Up, exactly what tapping
  // "Create One" on the login screen produces, so Sign Up's own back arrow
  // and its "Log in" link (both pop) land on Login instead of on nothing.
  Future<void> _useDifferentAccount() async {
    if (_navigatingAway) return;
    setState(() => _navigatingAway = true);
    // Taken before the await: the navigator outlives this screen's context.
    final navigator = Navigator.of(context, rootNavigator: true);
    final role = widget.pendingProfile?.role ?? widget.role;
    try {
      await _authService.signOut();
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      // Placed underneath without an animation of its own — only Sign Up
      // is seen sliding in.
      PageRouteBuilder(
        pageBuilder: (_, _, _) => _loginDoor(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
    // The web build is the Admin portal: there is no sign-up there.
    if (!kIsWeb) {
      navigator.push(slideRoute(RegisterScreen(initialRole: role)));
    }
  }

  // A short floating toast in the app's usual style (same as Add Product /
  // Support): dark green for confirmations, red for problems.
  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isError ? Colors.red.shade700 : AppTheme.dark,
          content: Text(message),
        ),
      );
  }

  // ----------------------------------------------------------
  // Six boxes drawn from one real text field laid over them — so typing,
  // backspace, paste and the keyboard's own "code from email" suggestion
  // all behave like a normal field.
  // ----------------------------------------------------------
  Widget _buildCodeInput() {
    final code = _codeController.text;
    final busy = _verifying || _navigatingAway;

    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _codeLength; i++) ...[
              if (i > 0) SizedBox(width: i == _codeLength ~/ 2 ? 14 : 6),
              Flexible(
                child: _CodeBox(
                  digit: i < code.length ? code[i] : '',
                  active:
                      _codeFocus.hasFocus &&
                      (i == code.length ||
                          (i == _codeLength - 1 && code.length == _codeLength)),
                ),
              ),
            ],
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: _codeController,
            focusNode: _codeFocus,
            enabled: !busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_codeLength),
            ],
            showCursor: false,
            enableInteractiveSelection: false,
            style: const TextStyle(color: Colors.transparent, fontSize: 1),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _verify(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _verifying || _navigatingAway;
    final canVerify = _codeController.text.length == _codeLength && !busy;
    final canResend = _cooldown <= 0 && !_requesting && !busy;

    return PopScope(
      // The system back button does what the arrow does.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AgriAppBar(
          onBack: _onBack,
          backEnabled: !busy,
          backTooltip: 'Back to login',
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Envelope icon ----
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 42,
                        color: AppTheme.dark,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Lilita One for the wordmark and the heading; everything
                    // else on this screen is Montserrat (AppTheme's helpers).
                    const AgriTradeText(fontSize: 30),
                    const SizedBox(height: 14),

                    Text(
                      'Verify Your Email',
                      style: GoogleFonts.lilitaOne(
                        fontSize: 24,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),

                    Text(
                      // "Requested", not "sent": this text is on screen
                      // whether or not the email has gone out yet.
                      "We've requested a verification email with a 6-digit "
                      'code for:',
                      style: AppTheme.body(size: 13.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),

                    // Where the code went — masked, never the full address.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        maskEmail(widget.email),
                        style: AppTheme.label().copyWith(
                          color: AppTheme.dark,
                          fontSize: 13.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 22),

                    _buildCodeInput(),
                    const SizedBox(height: 10),

                    Text(
                      'The code expires in 10 minutes.',
                      style: AppTheme.body(size: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // ---- Verify ----
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canVerify ? _verify : null,
                        style: AppTheme.primaryButton(),
                        child: busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Verify Code', style: AppTheme.buttonText()),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ---- Resend, with cooldown ----
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: canResend
                            ? () => _requestCode(resend: true)
                            : null,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppTheme.mid),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_requesting) ...[
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
                              _requesting
                                  ? 'Sending code…'
                                  : _cooldown > 0
                                  ? 'Resend Code in ${_cooldown}s'
                                  : 'Resend Code',
                              style: AppTheme.body(
                                color: canResend ? AppTheme.dark : Colors.grey,
                                size: 14,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ---- Escape hatch ----
                    TextButton(
                      onPressed: busy ? null : _useDifferentAccount,
                      child: Text(
                        'Use a different account',
                        style: AppTheme.body(size: 13),
                      ),
                    ),

                    const SizedBox(height: 8),
                    const EmailDeliveryNotice(
                      text:
                          'Please check your Inbox, including your Spam or '
                          'Junk folder. The email may take a few minutes to '
                          'arrive. If it is in Spam, mark it as "Not spam".',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// One digit of the code.
class _CodeBox extends StatelessWidget {
  final String digit;
  final bool active;

  const _CodeBox({required this.digit, required this.active});

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(maxWidth: 46),
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppTheme.accent.withValues(alpha: 0.35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active || filled ? AppTheme.dark : Colors.grey.shade300,
          width: active ? 2 : 1.2,
        ),
      ),
      child: Text(
        digit,
        style: AppTheme.heading(22).copyWith(color: AppTheme.dark),
      ),
    );
  }
}
