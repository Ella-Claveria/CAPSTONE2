import 'package:flutter/foundation.dart' show kIsWeb;
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
  bool get _isAdmin => widget.role == 'admin';

  // Human-readable label for the role subtitle under the AgriTrade+ logo.
  String? get _roleLabel {
    if (widget.role == null) return null;
    final t = AppLocalizations.of(context)!;
    if (_isAdmin) return t.adminLoginTitle;
    if (widget.role == 'farmer') return t.farmerLoginTitle;
    return t.buyerLoginTitle;
  }

  @override
  Widget build(BuildContext context) {
    final card = _LoginCard(
      isAdmin: _isAdmin,
      roleLabel: _roleLabel,
      role: widget.role,
      initialEmail: widget.initialEmail,
    );

    // The Admin Web build renders this screen as the app's root (see
    // AppBootstrap) — there's no previous screen to return to, and a much
    // wider canvas than the mobile card was designed for. Mobile keeps its
    // original plain layout completely untouched below; only kIsWeb gets
    // the full-bleed branded background and a centered, width-capped card
    // instead of the mobile card just being stretched across the page.
    if (kIsWeb) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/background.png', fit: BoxFit.cover),
            // Same dark green scrim family used behind the onboarding
            // photos, just applied evenly rather than bottom-weighted —
            // the card sits centered here, not anchored to the bottom.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xB30B2210), Color(0x800B2210)],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: card,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                child: card,
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

// The actual card content — logo, wordmark, role label, the shared
// email/password form, and (for non-admin doors only) the sign-up link.
// Identical on mobile and web; only what wraps it differs above.
class _LoginCard extends StatelessWidget {
  final bool isAdmin;
  final String? roleLabel;
  final String? role;
  final String? initialEmail;

  const _LoginCard({
    required this.isAdmin,
    required this.roleLabel,
    required this.role,
    required this.initialEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Center(child: AgriTradeText(fontSize: 30)),
          if (roleLabel != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(roleLabel!,
                  style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
            ),
          ],
          const SizedBox(height: 24),
          LoginFormFields(role: role, initialEmail: initialEmail),
          // Makes no sense for admin accounts (created manually via the
          // Firebase Console), so hidden for that door.
          if (!isAdmin) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    slideRoute(role != null ? RegisterScreen(initialRole: role!) : const RegisterScreen()),
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
    );
  }
}
