// ============================================================
// pending_approval_screen.dart
// ------------------------------------------------------------
// Put this at: lib/screens/pending_approval_screen.dart
//
// COVERS: FR-028 — "The system shall allow administrators to
// approve or reject farmer verification requests."
// (This is your paper's Figure 15, "Application Review
// Confirmation.")
//
// WHY THIS SCREEN EXISTS:
// Your paper says only VERIFIED local farmers may sell, so that
// buyers can trust the products. That means a farmer cannot go
// straight into the app after signing up — a Department of
// Agriculture officer must approve them first.
//
// This screen is where a farmer waits. It shows one of three
// states: pending, approved, or rejected.
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'farmer_home_screen.dart';
import 'login_screen.dart';

class PendingApprovalScreen extends StatefulWidget {
  final bool justVerified;

  const PendingApprovalScreen({super.key, this.justVerified = false});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _authService = AuthService();

  // Possible values: 'pending', 'approved', 'rejected'
  String _status = 'pending';
  bool _loading = true;
  bool _checkingStatus = false;
  bool _returningToLogin = false;
  bool _loginRedirectStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  // Firestore streams can re-emit the same value (e.g. a metadata-only
  // change), so this guards pushAndRemoveUntil from firing more than once.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _listenForApproval();
  }

  // Real-time: the admin's Approve/Reject action in the Web Dashboard
  // writes straight to users/{uid}, so this picks it up the moment it
  // happens — no need for the farmer to do anything on this screen.
  void _listenForApproval() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final status = (snap.data()?['approvalStatus'] ?? 'pending')
                .toString();
            setState(() {
              _status = status;
              _loading = false;
            });
            _maybeEnterApp(status);
          },
          onError: (_) {
            // Stay on whatever status was last known rather than leaving the
            // spinner running forever — the manual "Check status" button
            // still works independently of this listener.
            if (!mounted) return;
            setState(() => _loading = false);
          },
        );
  }

  void _maybeEnterApp(String status) {
    if (_navigated || status != 'approved') return;
    _navigated = true;
    _sub?.cancel();
    if (widget.justVerified) {
      _requireLoginToEnter();
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FarmerHomeScreen()),
      (route) => false,
    );
  }

  Future<void> _requireLoginToEnter() async {
    await _redirectToLogin(
      'Your application is approved. Please log in to continue.',
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------
  // "I-check ang status" — an explicit, one-shot re-fetch of the current
  // Firestore status, independent of the live listener above.
  // ----------------------------------------------------------
  Future<void> _checkStatus() async {
    if (_checkingStatus) return;
    setState(() => _checkingStatus = true);

    try {
      final status = await _authService.getFarmerApprovalStatus();
      if (!mounted) return;
      setState(() => _status = status);
      _maybeEnterApp(status);
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _returnToLogin() async {
    await _redirectToLogin();
  }

  Future<void> _redirectToLogin([String? message]) async {
    if (_loginRedirectStarted) return;
    _loginRedirectStarted = true;
    if (mounted) setState(() => _returningToLogin = true);
    _navigated = true;
    try {
      await _sub?.cancel().timeout(const Duration(seconds: 1));
    } catch (_) {}

    try {
      await _authService.signOut().timeout(const Duration(seconds: 3));
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut().timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          role: 'farmer',
          flashMessage: message,
          disableBackNavigation: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _status == 'rejected';

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
                  // ---- Status icon ----
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: rejected
                          ? Colors.red.withValues(alpha: 0.12)
                          : AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      rejected
                          ? Icons.cancel_outlined
                          : Icons.hourglass_top_rounded,
                      size: 42,
                      color: rejected ? Colors.red[700] : AppTheme.dark,
                    ),
                  ),
                  const SizedBox(height: 18),

                  const AgriTradeText(fontSize: 22),
                  const SizedBox(height: 14),

                  Text(
                    rejected
                        ? 'Application not approved'
                        : 'Application under review',
                    style: AppTheme.heading(20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  Text(
                    rejected
                        ? 'The Department of Agriculture did not approve '
                              'your application. Please contact their office '
                              'for clarification.'
                        : "You've submitted your farmer application, "
                              'including your agricultural certificate. A '
                              'Department of Agriculture officer now reviews '
                              'it to confirm you\'re a genuine farmer before '
                              'you can sell on AgriTrade+.',
                    style: AppTheme.body(size: 13.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),

                  if (!rejected) ...[
                    // ---- Requirements checklist ----
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: const [
                          _StepRow(label: 'Email verified', done: true),
                          SizedBox(height: 10),
                          _StepRow(label: 'Documents submitted', done: true),
                          SizedBox(height: 10),
                          _StepRow(label: 'Admin approval', done: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ---- 24-hour notice ----
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
                              'Admin approval typically takes up to 24 hours. '
                              "We'll notify you as soon as a decision is made.",
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

                    Text(
                      'Your email is verified and your required documents are '
                      'submitted. This application is waiting for admin review. '
                      'We will email you when a decision is made.',
                      style: AppTheme.body(size: 12.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // ---- Manual refresh ----
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading || _checkingStatus
                            ? null
                            : _checkStatus,
                        style: AppTheme.primaryButton(),
                        child: _checkingStatus
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Refreshing status',
                                    style: AppTheme.buttonText(),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.refresh_rounded, size: 19),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Check status',
                                    style: AppTheme.buttonText(),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: _loginRedirectStarted ? null : _returnToLogin,
                    child: _returningToLogin
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Back to login page',
                            style: AppTheme.body(size: 13),
                          ),
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

// ============================================================
// One row in the little progress checklist.
// ============================================================
class _StepRow extends StatelessWidget {
  final String label;
  final bool done;

  const _StepRow({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 20,
          color: done ? AppTheme.mid : Colors.grey,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            color: done ? AppTheme.dark : Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
