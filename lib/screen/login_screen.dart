import '../widgets/existing_account_dialog.dart';
import '../widgets/admin_session_dialogs.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'admin_login_view.dart';
import '../widgets/app_back_button.dart';
import '../widgets/login_form_fields.dart';
import '../widgets/login_hero.dart';
import '../l10n/tr.dart';

class LoginScreen extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  // Only the web admin door passes a specific role ('admin'), for the
  // slightly tighter role-mismatch check.
  final String? role;
  final String? flashMessage;
  final bool disableBackNavigation;

  /// The Admin was sent here because the account signed in on another
  /// device: says so in a popup once the page is up.
  final bool adminSessionEnded;

  /// With [adminSessionEnded]: this browser was signed out from Active
  /// Sessions on another device, and the popup says that instead.
  final bool adminSessionRevoked;

  const LoginScreen({
    super.key,
    this.role,
    this.flashMessage,
    this.disableBackNavigation = false,
    this.adminSessionEnded = false,
    this.adminSessionRevoked = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get _isAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    if (widget.adminSessionEnded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAdminSessionEndedDialog(
            context,
            revoked: widget.adminSessionRevoked,
          );
        }
      });
    }
  }

  // Human-readable label for the role subtitle under the AgriTrade+ logo.
  String? get _roleLabel {
    if (widget.role == null) return null;
    final t = tr(context);
    if (_isAdmin) return t.adminLoginTitle;
    if (widget.role == 'farmer') return t.farmerLoginTitle;
    return t.buyerLoginTitle;
  }

  @override
  Widget build(BuildContext context) {
    // The web admin door gets its own desktop layout; everything below is
    // the mobile farmer/buyer screen.
    if (_isAdmin) {
      return PopScope(
        canPop: !widget.disableBackNavigation,
        child: AdminLoginView(flashMessage: widget.flashMessage),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    // Keyboard up = give the form the room back instead of overflowing.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final heroHeight = keyboardOpen
        ? 120.0
        // Room for the typed-out headline between the logo and the sheet.
        : (screenHeight * 0.36).clamp(210.0, 310.0);
    final showBack = !kIsWeb && !widget.disableBackNavigation;

    return PopScope(
      canPop: !widget.disableBackNavigation,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ---- Hero: farm landscape photo + the AgriTrade+ lockup ----
            // The photo is set in LoginHero (bg_adminside.png, the Admin
            // login's too) — it just sits behind the logo lockup below.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: LoginHero(
                showBranding: !keyboardOpen,
                // Beside the Back button in the same corner.
                leadingInset: showBack ? AppBackButton.size + 12 : 0,
              ),
            ),

            // ---- White sheet, overlapping the photo ----
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: heroHeight - LoginHero.sheetOverlap,
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 24,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: kIsWeb ? 440 : double.infinity,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LoginHeader(roleLabel: _roleLabel),
                            if (widget.flashMessage != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(
                                    alpha: 0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                      color: AppTheme.dark,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.flashMessage!,
                                        style: AppTheme.body(size: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 26),
                            LoginFormFields(role: widget.role),
                            // Makes no sense for admin accounts (created
                            // manually via the Firebase Console), so hidden
                            // for that door.
                            if (!_isAdmin) ...[
                              const SizedBox(height: 14),
                              // Only "Create One." is tappable — the
                              // question before it is plain text.
                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        text: tr(context).noAccountSignUp,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      // Says so first if the account last used on this
                                      // phone already exists (a farmer waiting for
                                      // approval), instead of opening the form again.
                                      onTap: () => openRegistration(
                                        context,
                                        role: widget.role,
                                        onLoginPage: true,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        child: RichText(
                                          text: TextSpan(
                                            text: tr(context).createOne,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.dark,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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

            if (showBack)
              const SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(top: 8, left: 12),
                  // Over the hero photo, so the circle stays on.
                  child: AppBackButton(overImage: true),
                ),
              ),

            // No language switch here: the language is chosen inside the
            // app, in the farmer's and the buyer's Settings.
          ],
        ),
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
          tr(context).loginButton,
          style: const TextStyle(
            fontSize: 28,
            color: AppTheme.dark,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          roleLabel ?? tr(context).loginSubtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
