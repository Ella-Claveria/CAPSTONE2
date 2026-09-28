import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'register_screen.dart';
import '../widgets/login_form_fields.dart';
import '../widgets/login_hero.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  // Only the web admin door passes a specific role ('admin'), for the
  // slightly tighter role-mismatch check.
  final String? role;

  const LoginScreen({super.key, this.role});

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
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Keyboard up = give the form the room back instead of overflowing.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final heroHeight = keyboardOpen ? 120.0 : (screenHeight * 0.36).clamp(200.0, 320.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ---- Hero: brand gradient + the AgriTrade+ lockup ----
          // Swap assets/images/login_hero.png for your own photo whenever
          // you're ready — it just sits behind the logo lockup below.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: LoginHero(showBranding: !keyboardOpen),
          ),

          // ---- White sheet, overlapping the photo ----
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: kIsWeb ? 440 : double.infinity),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LoginHeader(roleLabel: _roleLabel),
                          const SizedBox(height: 26),
                          LoginFormFields(role: widget.role),
                          // Makes no sense for admin accounts (created
                          // manually via the Firebase Console), so hidden
                          // for that door.
                          if (!_isAdmin) ...[
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    slideRoute(widget.role != null
                                        ? RegisterScreen(initialRole: widget.role!)
                                        : const RegisterScreen()),
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
              ),
            ),
          ),

          if (!kIsWeb)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Login" + subtitle (or role label), sitting at the top of the white
/// sheet — the AgriTrade+ logo itself now lives in the hero above, so it
/// isn't repeated here.
class _LoginHeader extends StatelessWidget {
  final String? roleLabel;
  const _LoginHeader({required this.roleLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.loginButton,
          style: const TextStyle(fontSize: 28, color: AppTheme.dark, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          roleLabel ?? AppLocalizations.of(context)!.loginSubtitle,
          style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
