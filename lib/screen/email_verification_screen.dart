// ============================================================
// email_verification_screen.dart
// ------------------------------------------------------------
// COVERS: Objective 4.2 — "Requiring mandatory account
// verification via email for all registered users."
//
// HOW IT WORKS:
// After signing up, Firebase sends a verification link to the
// user's email. Until they click that link, their account is
// "unverified". This screen waits for that to happen, checking
// automatically every 4 seconds — the user doesn't even need to
// press anything, they just tap the link, switch back to the
// app, and it moves on by itself.
//
// Once verified, the full profile collected at registration
// (name, barangay, certificate, etc. — see PendingRegistrationProfile)
// is written to Firestore for the first time here, never before —
// see AuthService.completeRegistration's doc comment for why.
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String role; // 'farmer' or 'buyer'
  final String email; // shown on screen so they know where to look
  final bool sendInitialEmail;
  // Everything collected on the registration form that still needs to be
  // written to Firestore once verification succeeds (see
  // AuthService.completeRegistration). Null when resuming an existing
  // unverified session from a fresh app launch — _checkVerified falls
  // back to AuthService.loadPendingProfile in that case, since this
  // constructor argument doesn't survive the app being closed.
  final PendingRegistrationProfile? pendingProfile;

  const EmailVerificationScreen({
    super.key,
    required this.role,
    required this.email,
    this.sendInitialEmail = true,
    this.pendingProfile,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _authService = AuthService();

  Timer? _pollTimer; // checks verification automatically
  Timer? _cooldownTimer; // counts down the resend button
  int _cooldown = 0; // seconds left before resend is allowed
  bool _checking = false;
  bool _navigatingAway = false;

  // The link we most recently sent is only honored by this screen for 5
  // minutes — see _checkExpiry's doc comment for the caveat on what that
  // actually means.
  static const _linkValidFor = Duration(minutes: 5);
  DateTime? _emailSentAt;
  bool _expired = false;

  @override
  void initState() {
    super.initState();

    // Registration reaches this screen once after creating the account, so
    // send exactly one initial message here. Existing unverified sessions
    // enter with sendInitialEmail=false and can resend only on request.
    if (widget.sendInitialEmail) _sendEmail(initial: true);

    // Then quietly check every 4 seconds whether they've clicked it, and
    // whether the 5-minute window on the link we sent has run out.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkVerified(silent: true);
      _checkExpiry();
    });
  }

  @override
  void dispose() {
    // Very important: stop the timers when leaving this screen,
    // or they keep running in the background and cause errors.
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------
  // Send (or resend) the verification email.
  // ----------------------------------------------------------
  Future<void> _sendEmail({bool initial = false}) async {
    final error = await _authService.sendVerificationEmail();
    if (!mounted) return;

    if (error != null) {
      _showMessage(error);
      return;
    }

    if (!initial) {
      _showMessage('Verification link resent.');
    }

    // Start a 60-second cooldown so they can't spam the button, and reset
    // this screen's 5-minute window on the freshly-sent link.
    setState(() {
      _cooldown = 60;
      _emailSentAt = DateTime.now();
      _expired = false;
    });
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

  // Firebase itself doesn't expose a way to shorten a verification link's
  // own validity from the client SDK, so this is this screen's own
  // enforcement instead: once 5 minutes pass without verifying, it stops
  // encouraging use of the link it already sent and pushes "Resend email"
  // instead — but if the original link still happens to get clicked after
  // that (Firebase's own, longer expiry hasn't necessarily run out), it's
  // still honored rather than fought; _checkVerified keeps polling
  // regardless of _expired.
  void _checkExpiry() {
    if (_expired || _emailSentAt == null) return;
    if (DateTime.now().difference(_emailSentAt!) >= _linkValidFor) {
      setState(() => _expired = true);
    }
  }

  // ----------------------------------------------------------
  // Ask Firebase: has this user clicked the link yet?
  //
  // "silent" means it was the automatic check, so we don't show
  // an error message if they haven't verified yet.
  // ----------------------------------------------------------
  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking || _navigatingAway) return;
    _checking = true;

    if (!silent) setState(() {});

    try {
      final verified = await _authService.isEmailVerified();
      if (!mounted) return;

      if (verified) {
        _navigatingAway = true;

        final verificationError = await _authService
            .refreshVerifiedEmailToken();
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
          _pollTimer?.cancel();
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const PendingApprovalScreen(justVerified: true),
            ),
            (route) => false,
          );
        } else {
          await _backToLogin();
        }
      } else if (!silent) {
        _showMessage('Not verified yet. Please check your inbox.');
      }
    } catch (_) {
      if (mounted) {
        _navigatingAway = false;
        _showMessage('Could not finish verification. Please try again.');
      }
    } finally {
      _checking = false;
      if (mounted) setState(() {});
    }
  }

  // Writes the full Firestore profile for the very first time — see
  // AuthService.completeRegistration's doc comment. Skipped (not an
  // error) if a doc already exists for this uid, which covers both "this
  // already ran once" (e.g. a duplicate poll tick) and a legacy account
  // that was fully registered before this deferred-write design existed.
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
    );
    if (error == null) await _authService.clearPendingProfile(uid);
    return error;
  }

  // ----------------------------------------------------------
  // Verifying an email signs the account out again and sends them back to
  // the login screen — the account isn't considered "logged in" for real
  // until they actually enter their password again afterward. This is a
  // deliberate security step, not a bug: it stops anyone who intercepted
  // the (still-open) sign-up session on this device from riding it straight
  // into the app just because the link got clicked.
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
        ),
      ),
      (route) => false, // clears the back stack
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
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

                  const AgriTradeText(fontSize: 22),
                  const SizedBox(height: 14),

                  Text(
                    'Verify your email',
                    style: AppTheme.heading(21),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'We sent a verification link to:',
                    style: AppTheme.body(size: 13.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // The email address, highlighted.
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
                      widget.email,
                      style: AppTheme.label().copyWith(
                        color: AppTheme.dark,
                        fontSize: 13.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Open the email, tap the link, then come back here. '
                    'This screen will continue on its own.',
                    style: AppTheme.body(size: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),

                  if (_expired) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.schedule,
                            color: Colors.amber.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "That link has expired. Tap \"Resend email\" below to get a new one.",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ---- Manual check button ----
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _checking || _navigatingAway
                          ? null
                          : () => _checkVerified(silent: false),
                      style: AppTheme.primaryButton(),
                      child: _checking
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              "I've verified it",
                              style: AppTheme.buttonText(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ---- Resend, with cooldown ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _cooldown > 0 ? null : () => _sendEmail(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppTheme.mid),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        _cooldown > 0
                            ? 'Resend in ${_cooldown}s'
                            : 'Resend email',
                        style: AppTheme.body(
                          color: _cooldown > 0 ? Colors.grey : AppTheme.dark,
                          size: 14,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ---- Escape hatch ----
                  TextButton(
                    onPressed: () async {
                      await _authService.signOut();
                      if (!context.mounted) return;
                      // Reached either via pushReplacement (fresh
                      // registration, LoginScreen still underneath) or
                      // pushAndRemoveUntil (a resumed unverified session,
                      // nothing underneath) — popUntil(isFirst) would be a
                      // silent no-op in the second case, so go to login
                      // directly instead of relying on what's left below.
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(role: widget.role),
                        ),
                        (route) => false,
                      );
                    },
                    child: Text(
                      'Use a different account',
                      style: AppTheme.body(size: 13),
                    ),
                  ),

                  const SizedBox(height: 4),
                  Text(
                    "If it's not in your Inbox, check Spam or Promotions. "
                    'If it\'s there, mark it as "Not spam".',
                    style: AppTheme.body(size: 11.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
