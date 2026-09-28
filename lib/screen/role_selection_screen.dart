import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/login_form_fields.dart';
import '../widgets/login_hero.dart';
import 'register_screen.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';

/// The app's front door: "Log In" or "Don't have an account? Create One."
/// No role is picked here — login itself is role-agnostic (see
/// LoginScreen), and farmer vs. buyer is a toggle right on the registration
/// form (see RegisterScreen). Remembering credentials between sessions is
/// left entirely to the OS's own password manager (see LoginFormFields).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final heroHeight = keyboardOpen ? 120.0 : (screenHeight * 0.36).clamp(200.0, 320.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ---- Hero: same branded header as LoginScreen — this is the ----
          // ---- app's actual front door, so it gets the same treatment. ----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: LoginHero(showBranding: !keyboardOpen),
          ),

          // ---- White sheet, overlapping the hero ----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: heroHeight - 32,
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, -8))],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.loginButton,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, color: AppTheme.dark, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context)!.loginSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 26),
                      const LoginFormFields(),

                      const SizedBox(height: 18),

                      // ----- Create account -----
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(context, slideRoute(const RegisterScreen()));
                          },
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black87),
                              children: [
                                TextSpan(text: AppLocalizations.of(context)!.noAccountSignUp),
                                TextSpan(
                                  text: AppLocalizations.of(context)!.createOne,
                                  style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: AppTheme.dark),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
