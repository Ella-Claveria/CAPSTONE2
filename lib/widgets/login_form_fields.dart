import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/auth_routing_service.dart';
import '../services/audit_log_service.dart';
import '../theme/app_theme.dart';
import '../screen/auth_route_handler.dart';
import '../screen/forgot_password_screen.dart';
import '../screen/google_complete_profile_screen.dart';
import '../screen/page_transitions.dart';
import 'glow_field.dart';
import 'role_mismatch_dialog.dart';
import '../l10n/app_localizations.dart';

/// The email/password sign-in form — fields, Forgot Password, and the
/// submit button — plus the whole sign-in flow behind it. Shared by
/// [LoginScreen] (role-specific logins) and the entry screen (embedded
/// inline, right under the logo, over the background photo) so both stay in
/// sync instead of drifting apart across edits.
///
/// Remembering credentials is left entirely to the OS's own password
/// manager (Google Password Manager / iCloud Keychain), via the
/// [AutofillGroup] + autofillHints below — the app itself never stores an
/// email or password on this device.
///
/// The one exception is the admin door (role == 'admin'): that's a web
/// login on a single shared office machine, and Chrome's native
/// save-password popup is unreliable inside a Flutter SPA (the page never
/// truly navigates), so the admin email/password are additionally saved
/// straight to this device's local storage after a successful login and
/// pre-filled on the next visit — see [_loadSavedAdminCredentials]/
/// [_saveAdminCredentials].
class LoginFormFields extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  final String? role;

  const LoginFormFields({super.key, this.role});

  @override
  State<LoginFormFields> createState() => _LoginFormFieldsState();
}

class _LoginFormFieldsState extends State<LoginFormFields> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;

  bool get _isAdmin => widget.role == 'admin';

  static const _adminEmailKey = 'admin_saved_email';
  static const _adminPasswordKey = 'admin_saved_password';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _loadSavedAdminCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAdminCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_adminEmailKey);
      final password = prefs.getString(_adminPasswordKey);
      if (!mounted) return;
      if (email != null) _emailController.text = email;
      if (password != null) _passwordController.text = password;
    } catch (_) {
      // Non-fatal — fields just stay empty, same as a first-ever visit.
    }
  }

  Future<void> _saveAdminCredentials(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_adminEmailKey, email);
      await prefs.setString(_adminPasswordKey, password);
    } catch (_) {
      // Non-fatal — login already succeeded either way.
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }
    setState(() => _loading = true);
    final error = await _authService.logIn(
      email: email,
      password: password,
      // The admin door's role/platform enforcement happens below, via
      // AuthRoutingService, so its exact required messaging is shown —
      // skip the generic role-mismatch check only for that door.
      expectedRole: _isAdmin ? null : widget.role,
    );
    if (!mounted) return;

    if (error != null && error.startsWith('ROLE_MISMATCH:')) {
      setState(() => _loading = false);
      final registeredRole = error.substring('ROLE_MISMATCH:'.length);
      showRoleMismatchDialog(context, registeredRole);
      return;
    }

    if (error != null) {
      // Only the admin login door is audited — the mobile farmer/buyer
      // doors share this same widget but aren't in scope for the Admin
      // Portal's audit trail (see AuditLogService).
      if (_isAdmin) AuditLogService.logPreAuth(AuditAction.loginFailed, email: email, details: error);
      setState(() => _loading = false);
      _showMessage(error);
      return;
    }

    // Logged in with Firebase — now the one, shared source of truth for
    // "where does this account belong": reads users/{uid}.role (and
    // approvalStatus for farmers), and enforces the mobile-vs-web platform
    // rule. See AuthRoutingService for the actual decision logic.
    final uid = _authService.currentUid;
    final result = uid == null
        ? const AuthRouteResult(
            decision: AuthRouteDecision.error,
            message: 'Something went wrong. Please try again.',
          )
        : await AuthRoutingService.decide(uid);
    if (!mounted) return;

    if (_isAdmin) {
      if (result.decision == AuthRouteDecision.adminDashboard) {
        AuditLogService.log(AuditAction.loginSuccess, 'Signed in to the Admin Portal.');
        _saveAdminCredentials(email, password);
      } else {
        // Valid credentials, but this account isn't an admin (or something
        // else blocked routing) — still a failed attempt to reach the
        // admin dashboard, worth its own audit entry.
        AuditLogService.logPreAuth(
          AuditAction.loginFailed,
          email: email,
          details: result.message ?? 'Not authorized for the Admin Dashboard.',
        );
      }
    }

    final role = result.role;
    // Tells the OS's autofill service (Google Password Manager / iCloud
    // Keychain) this login attempt is done, so it can offer its own native
    // "Save password?" prompt — the app never stores the credentials itself.
    TextInput.finishAutofillContext();

    // Logging in (as opposed to just having registered) means this is an
    // existing account, not a first-time user — so the feature walkthrough
    // on their home screen should never trigger, even on a device that
    // hasn't seen it yet (a new phone, a reinstall, a cleared app). A brand
    // new registrant never passes through here on their way to their home
    // screen (register → verify → [approval] → home), so this can't
    // accidentally suppress a genuinely new user's first-time tour.
    if (result.isSignedIn && (role == 'farmer' || role == 'buyer')) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('walkthrough_seen_$role', true);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loading = false);
    // pushAndRemoveUntil (inside applyAuthRouteResult) clears splash/
    // role-selection/login from the stack, so the back button on Home has
    // nothing left to pop to.
    await applyAuthRouteResult(context, result);
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    final result = await _authService.signInWithGoogle();
    if (!mounted) return;

    switch (result.outcome) {
      case GoogleSignInOutcome.cancelled:
        setState(() => _googleLoading = false);
        return;

      case GoogleSignInOutcome.error:
        setState(() => _googleLoading = false);
        _showMessage(result.message ?? 'Google sign-in failed. Please try again.');
        return;

      case GoogleSignInOutcome.needsProfile:
        setState(() => _googleLoading = false);
        Navigator.push(
          context,
          slideRoute(GoogleCompleteProfileScreen(
            uid: result.uid!,
            email: result.email ?? '',
            initialName: result.displayName,
            initialRole: widget.role ?? 'buyer',
          )),
        );
        return;

      case GoogleSignInOutcome.signedIn:
        final routeResult = await AuthRoutingService.decide(result.uid!);
        if (!mounted) return;

        // Same role/door enforcement as the password path above — a buyer
        // account signing in through the farmer-specific door, etc.
        if (!_isAdmin &&
            widget.role != null &&
            routeResult.role != null &&
            routeResult.role != widget.role) {
          setState(() => _googleLoading = false);
          await _authService.signOut();
          if (!mounted) return;
          showRoleMismatchDialog(context, routeResult.role!);
          return;
        }

        final role = routeResult.role;
        if (routeResult.isSignedIn && (role == 'farmer' || role == 'buyer')) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('walkthrough_seen_$role', true);
          } catch (_) {}
        }

        if (!mounted) return;
        setState(() => _googleLoading = false);
        await applyAuthRouteResult(context, routeResult);
        return;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(AppLocalizations.of(context)!.emailAddress, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GlowField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          hint: 'you@example.com',
          icon: Icons.email_outlined,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          autofillHints: const [AutofillHints.email, AutofillHints.username],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppLocalizations.of(context)!.password, style: const TextStyle(fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                slideRoute(ForgotPasswordScreen(
                  initialEmail: _emailController.text.trim(),
                  isAdmin: _isAdmin,
                )),
              ),
              child: Text(AppLocalizations.of(context)!.forgotPassword, style: const TextStyle(color: AppTheme.dark, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GlowField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          hint: 'Password',
          icon: Icons.lock_outline,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _login(),
          autofillHints: const [AutofillHints.password],
          suffix: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _login,
            style: AppTheme.primaryButton(),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppLocalizations.of(context)!.loginButton, style: AppTheme.buttonText()),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                    ],
                  ),
          ),
        ),
        // Admin accounts are created manually via the Firebase Console
        // (see the header comment on _login's expectedRole), so there's no
        // "sign up" concept for that door — same reasoning excludes Google
        // sign-in there too.
        if (!_isAdmin) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('or', style: TextStyle(color: Colors.grey[500], fontSize: 12.5)),
              ),
              Expanded(child: Divider(color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: (_loading || _googleLoading) ? null : _continueWithGoogle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _googleLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset('assets/images/google_logo.svg', width: 19, height: 19),
                        const SizedBox(width: 10),
                        Text(
                          'Continue with Google',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ],
      ),
    );
  }
}
