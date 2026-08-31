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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkStatus();

    // Check again every 10 seconds, in case the admin approves
    // while the farmer is still looking at this screen.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkStatus(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------
  // Ask the database what the admin has decided so far.
  // ----------------------------------------------------------
  Future<void> _checkStatus({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);

    final status = await _authService.getFarmerApprovalStatus();

    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });

    // Approved? Send them into the app.
    if (status == 'approved') {
      _pollTimer?.cancel();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const FarmerHomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _status == 'rejected';

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