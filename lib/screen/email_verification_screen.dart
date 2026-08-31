// ============================================================
// email_verification_screen.dart
// ------------------------------------------------------------
// Put this at: lib/screens/email_verification_screen.dart
//
// COVERS: Objective 4.2 — "Requiring mandatory account
// verification via email for all registered users."
// (This is your paper's Figure 16.)
//
// HOW IT WORKS:
// After signing up, Firebase can send a verification link to the
// user's email. Until they click that link, their account is
// "unverified". This screen waits for that to happen.
//
// It checks automatically every 4 seconds, so the user doesn't
// even need to press anything — they just tap the link in their
// email, switch back to the app, and it moves on by itself.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'pending_approval_screen.dart';
import 'buyer_marketplace_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String role; // 'farmer' or 'buyer'
  final String email; // shown on screen so they know where to look

  const EmailVerificationScreen({
    super.key,
    required this.role,
    required this.email,
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

  bool get _isFarmer => widget.role == 'farmer';

  @override
  void initState() {
    super.initState();

    // Send the first verification email right away.
    _sendEmail(initial: true);

    // Then quietly check every 4 seconds whether they've clicked it.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkVerified(silent: true),
    );
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
      _showMessage('Naipadala ulit ang verification link.');
    }

    // Start a 60-second cooldown so they can't spam the button.
    setState(() => _cooldown = 60);
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
  // Ask Firebase: has this user clicked the link yet?
  //
  // "silent" means it was the automatic check, so we don't show
  // an error message if they haven't verified yet.
  // ----------------------------------------------------------
  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking) return; // don't run two checks at once
    _checking = true;

    if (!silent) setState(() {});

    final verified = await _authService.isEmailVerified();

    _checking = false;
    if (!mounted) return;

    if (verified) {
      _pollTimer?.cancel();
      _goToNextScreen();
    } else if (!silent) {
      _showMessage('Hindi pa na-verify. Pakicheck ang inbox mo.');
      setState(() {});
    }
  }

  // ----------------------------------------------------------
  // Where they go after verifying depends on their role.
  //
  //   Buyer  → straight into the marketplace
  //   Farmer → still needs admin approval first (FR-028)
  // ----------------------------------------------------------
  void _goToNextScreen() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => _isFarmer
            ? const PendingApprovalScreen()
            : const BuyerMarketplaceScreen(),
      ),
      (route) => false, // clears the back stack
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.dark,
          image: DecorationImage(
            image: AssetImage('assets/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: AppTheme.authCard(),
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
                      'Nagpadala kami ng verification link sa:',
                      style: AppTheme.body(size: 13.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),

                    // The email address, highlighted.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
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
                      'Buksan ang email, pindutin ang link, '
                      'tapos bumalik dito. Awtomatiko itong '
                      'magpapatuloy.',
                      style: AppTheme.body(size: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),

                    // ---- Manual check button ----
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _checkVerified(silent: false),
                        style: AppTheme.primaryButton(),
                        child: Text(
                          'Na-verify ko na',
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
                            color: _cooldown > 0
                                ? Colors.grey
                                : AppTheme.dark,
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
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      child: Text(
                        'Gumamit ng ibang account',
                        style: AppTheme.body(size: 13),
                      ),
                    ),

                    const SizedBox(height: 4),
                    Text(
                      'Tip: tingnan din ang Spam folder.',
                      style: AppTheme.body(size: 11.5),
                      textAlign: TextAlign.center,
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