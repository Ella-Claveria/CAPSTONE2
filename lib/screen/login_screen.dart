import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'register_screen.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/login_form_fields.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';


class LoginScreen extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  // Only the "remembered last login" shortcut from AppRouter still passes a
  // specific role, for the slightly tighter role-mismatch check.
  final String? role;

  // Set when arriving from a saved-account tile on the entry screen — the
  // email is ready to go, they just need to type that account's password.
  final String? initialEmail;

  const LoginScreen({super.key, this.role, this.initialEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get _isFarmer => widget.role == 'farmer';
  bool get _isAdmin => widget.role == 'admin';

  // Human-readable label for the role subtitle under the AgriTrade+ logo.
  String get _roleLabel {
    final t = AppLocalizations.of(context)!;
    if (_isAdmin) return t.adminLoginTitle;
    if (_isFarmer) return t.farmerLoginTitle;
    return t.buyerLoginTitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            // ---- Centered, scrollable form card — everything (fields, ----
            // ---- the Login button, and the sign-up link) lives inside ----
            // ---- one card; only the back arrow (below) floats outside ----
            // ---- it, so it stays put no matter how far this scrolls.  ----
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/logo.png',
                          width: 80,
                          height: 80,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 80,
                              height: 80,
                              decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
                              child: const Icon(Icons.agriculture, size: 42, color: Colors.white),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(AppLocalizations.of(context)!.welcomeTo,
                            style: const TextStyle(fontSize: 20, color: Colors.black87)),
                      ),
                      const Center(child: AgriTradeText(fontSize: 30)),
                      if (widget.role != null) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: Text(_roleLabel,
                              style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
                        ),
                      ],
                      const SizedBox(height: 24),
                      LoginFormFields(role: widget.role, initialEmail: widget.initialEmail),
                      // Makes no sense for admin accounts (created manually
                      // via the Firebase Console), so hidden for that door.
                      if (!_isAdmin) ...[
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              final role = widget.role;
                              Navigator.push(
                                context,
                                slideRoute(role != null ? RegisterScreen(initialRole: role) : const RegisterScreen()),
                              );
                            },
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black87),
                                children: [
                                  TextSpan(text: AppLocalizations.of(context)!.noAccountSignUp),
                                  TextSpan(
                                      text: AppLocalizations.of(context)!.createOne,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.dark)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ---- Back arrow, floating above everything at the top-left ----
            // ---- corner — not part of the card, so it never scrolls.   ----
            // ---- This form is short enough to never need scrolling, so ----
            // ---- unlike Register it never needs a backdrop behind it.  ----
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.dark),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
