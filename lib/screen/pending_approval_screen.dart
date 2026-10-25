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
// straight into the app after signing up — an officer of the
// Agricultural Office of Laurel, Batangas must approve them first.
//
// This screen is where a farmer waits. It shows one of three
// states: pending, approved, or rejected.
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../services/first_entry_after_approval.dart';
import 'login_screen.dart';

class PendingApprovalScreen extends StatefulWidget {
  final bool justVerified;

  /// The decision already known — from the approval notification that
  /// opened this screen ('approved' / 'rejected'), so it shows even when
  /// the farmer is signed out and the account cannot be read.
  final String? initialStatus;

  /// The office's reason, when [initialStatus] is 'rejected'.
  final String? initialReason;

  const PendingApprovalScreen({
    super.key,
    this.justVerified = false,
    this.initialStatus,
    this.initialReason,
  });

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _authService = AuthService();

  // Possible values: 'pending', 'approved', 'rejected'
  late String _status = switch (widget.initialStatus) {
    'approved' || 'rejected' => widget.initialStatus!,
    _ => 'pending',
  };
  bool _loading = true;
  bool _checkingStatus = false;
  bool _returningToLogin = false;
  bool _loginRedirectStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  // The office's reason for not approving, kept with the application.
  late String _rejectionReason = (widget.initialReason ?? '').trim();
  bool _reasonAsked = false;

  Future<void> _loadRejectionReason() async {
    if (_reasonAsked) return;
    _reasonAsked = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final application = await FirebaseFirestore.instance
          .collection('verificationDocs')
          .doc(uid)
          .get();
      final reason = (application.data()?['rejectionReason'] ?? '')
          .toString()
          .trim();
      if (mounted && reason.isNotEmpty) {
        setState(() => _rejectionReason = reason);
      }
    } catch (_) {
      // Shown without a reason; the office can still be asked.
      _reasonAsked = false;
    }
  }

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
    // Registered and verified, now waiting: the moment notifications are
    // worth having. Explained first, asked once per phone, and declining
    // changes nothing here (see NotificationPermissionPrompt).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationPermissionPrompt.instance.onEnteredApp(context);
      // Puts this phone on the account's push list when notifications are
      // allowed (now, or from before) — it never asks by itself. A farmer
      // who has just registered reaches this screen without passing the
      // app's usual start-up registration.
      try {
        await PushNotificationService().setupFCM();
      } catch (_) {}
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Signed out (opened from the notification): the decision it carried
      // is what is shown.
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
            if (_navigated) return;
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

  // Approved: never straight into the app. For security the farmer logs in
  // again first — however they reached this screen (just registered, a
  // login, the app reopened while waiting, or the approval notification).
  // The screen shows the approval (Admin approval ticked) with a Log In
  // button rather than jumping away, so the decision is seen.
  void _maybeEnterApp(String status) {
    if (_navigated || status != 'approved') return;
    _navigated = true;
    _sub?.cancel();
    // That login is still this farmer's first time in the app, so the
    // walkthrough is kept for it (see LoginFormFields).
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) FirstEntryAfterApproval.mark(uid);
  }

  Future<void> _logInAfterApproval() => _redirectToLogin(
    'Your application is approved. Please log in to continue.',
  );

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
      // Spins at least a moment, so the check is seen even when the answer
      // comes back at once.
      final results = await Future.wait([
        _authService.getFarmerApprovalStatus(),
        Future<void>.delayed(const Duration(milliseconds: 800)),
      ]);
      final status = results.first as String;
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
      // Still under review: this phone stays on the account's push list,
      // so the office's decision reaches it while signed out.
      await _authService
          .signOut(
            reason: 'farmer returned to login from the approval screen',
            keepPushToken: _status == 'pending',
          )
          .timeout(const Duration(seconds: 3));
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
    final approved = _status == 'approved';
    if (rejected && _rejectionReason.isEmpty) _loadRejectionReason();

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
                          : approved
                          ? Icons.verified_rounded
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
                        : approved
                        ? 'Application approved'
                        : 'Application under review',
                    style: AppTheme.heading(20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  Text(
                    rejected
                        ? 'The Agricultural Office of Laurel, Batangas did not '
                              'approve your application. Please contact their office '
                              'for clarification.'
                        : approved
                        ? 'The Agricultural Office of Laurel, Batangas has '
                              'approved your farmer application. Log in to '
                              'start selling on AgriTrade+.'
                        : 'The Agricultural Office of Laurel, Batangas is '
                              'reviewing your application. You can start '
                              'selling once it is approved.',
                    style: AppTheme.body(size: 13.5),
                    textAlign: TextAlign.center,
                  ),
                  if (rejected && _rejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reason',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.red[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _rejectionReason,
                            style: AppTheme.body(size: 13.5),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        children: [
                          const _StepRow(label: 'Email verified', done: true),
                          const SizedBox(height: 10),
                          const _StepRow(
                            label: 'Application submitted',
                            done: true,
                          ),
                          const SizedBox(height: 10),
                          _StepRow(label: 'Admin approval', done: approved),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (approved) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loginRedirectStarted
                            ? null
                            : _logInAfterApproval,
                        style: AppTheme.primaryButton(),
                        child: _returningToLogin
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Log In to Continue',
                                style: AppTheme.buttonText(),
                              ),
                      ),
                    ),
                  ],

                  if (!rejected && !approved) ...[
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
                    const SizedBox(height: 20),

                    // ---- Manual refresh ----
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading || _checkingStatus
                            ? null
                            : _checkStatus,
                        style: AppTheme.primaryButton(),
                        // The refresh icon spins while the status is checked.
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SpinningIcon(
                              icon: Icons.refresh_rounded,
                              spinning: _checkingStatus,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _checkingStatus
                                  ? 'Checking status…'
                                  : 'Check status',
                              style: AppTheme.buttonText(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  if (!approved)
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

// ============================================================
// An icon that turns while [spinning] — the Check status button's refresh
// icon, so the check is seen to be happening.
// ============================================================
class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final bool spinning;

  const _SpinningIcon({required this.icon, required this.spinning});

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _turn.repeat();
  }

  @override
  void didUpdateWidget(_SpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!widget.spinning && _turn.isAnimating) {
      // Finishes the turn it is on, so it stops upright.
      _turn.forward(from: _turn.value);
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _turn, child: Icon(widget.icon, size: 19));
}
