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

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _authService = AuthService();

  // Possible values: 'pending', 'approved', 'rejected'
  String _status = 'pending';
  bool _loading = true;
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
    _sub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) {
      if (!mounted) return;
      final status = (snap.data()?['approvalStatus'] ?? 'pending').toString();
      setState(() {
        _status = status;
        _loading = false;
      });
      _maybeEnterApp(status);
    });
  }

  void _maybeEnterApp(String status) {
    if (_navigated || status != 'approved') return;
    _navigated = true;
    _sub?.cancel();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FarmerHomeScreen()),
      (route) => false,
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
    setState(() => _loading = true);

    final status = await _authService.getFarmerApprovalStatus();

    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
    _maybeEnterApp(status);
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _status == 'rejected';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.dark,
          image: DecorationImage(
            image: AssetImage('assets/images/onboarding_1_farming.png'),
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
                          ? 'Hindi naaprubahan ng Department of '
                              'Agriculture ang iyong application. '
                              'Maaari kang makipag-ugnayan sa kanilang '
                              'opisina para sa paglilinaw.'
                          : 'Naipasa na ang iyong farmer application. '
                              'Sinusuri ito ng isang opisyal ng '
                              'Department of Agriculture upang matiyak '
                              'na tunay na magsasaka ang nagbebenta sa '
                              'AgriTrade+.',
                      style: AppTheme.body(size: 13.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),

                    if (!rejected) ...[
                      // ---- Simple 3-step progress ----
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: const [
                            _StepRow(
                              label: 'Account created',
                              done: true,
                            ),
                            SizedBox(height: 10),
                            _StepRow(
                              label: 'Email verified',
                              done: true,
                            ),
                            SizedBox(height: 10),
                            _StepRow(
                              label: 'Admin approval',
                              done: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      Text(
                        'Aabisuhan ka namin kapag naaprubahan na. '
                        'Awtomatikong nag-che-check ang screen na ito.',
                        style: AppTheme.body(size: 12.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // ---- Manual refresh ----
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _loading ? null : () => _checkStatus(),
                          style: AppTheme.primaryButton(),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'I-check ang status',
                                  style: AppTheme.buttonText(),
                                ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: () async {
                        await _authService.signOut();
                        if (!context.mounted) return;
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      child: Text(
                        'Mag-log out',
                        style: AppTheme.body(size: 13),
                      ),
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