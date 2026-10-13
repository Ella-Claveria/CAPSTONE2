import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/auth_routing_service.dart';
import '../services/admin_session_service.dart';
import '../services/audit_log_service.dart';
import '../services/registration_guard.dart';
import 'admin_session_dialogs.dart';
import '../theme/app_theme.dart';
import '../screen/auth_route_handler.dart';
import '../screen/forgot_password_screen.dart';
import '../screen/google_complete_profile_screen.dart';
import '../screen/page_transitions.dart';
import 'glow_field.dart';
import 'login_lockout_dialog.dart';
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
/// password on this device. The admin email alone is remembered.
///
/// Legacy locally saved admin passwords are removed when the form opens.
class LoginFormFields extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  final String? role;

  /// Opens the password-reset form with the email typed so far. Left
  /// null, Forgot Password opens as its own screen (mobile); the Admin
  /// sign-in page passes this to swap its form in place instead.
  final ValueChanged<String>? onForgotPassword;

  const LoginFormFields({super.key, this.role, this.onForgotPassword});

  /// Removes passwords persisted by older versions of the admin form.
  static Future<void> clearSavedAdminPassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_LoginFormFieldsState._adminPasswordKey);
    } catch (_) {}
  }

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
  // The "attempts remaining" warning from the last failed attempt, shown
  // under the Password field until the next attempt or edit.
  String? _loginError;

  bool get _isAdmin => widget.role == 'admin';

  static const _adminEmailKey = 'admin_saved_email';
  static const _adminPasswordKey = 'admin_saved_password';
  static const _noAdminAccessMessage =
      'This account does not have administrator access.';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _loadSavedAdminEmail();
    _emailController.addListener(_clearLoginError);
    _passwordController.addListener(_clearLoginError);
  }

  // Editing either field means the message is about something no longer
  // typed in. This only hides the text: the failed-attempt count is kept
  // by the server and is not affected.
  void _clearLoginError() {
    if (_loginError != null) setState(() => _loginError = null);
  }

  // The message under the Password field. Takes no room when there is
  // nothing to say.
  Widget _loginErrorText() {
    final message = _loginError;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: _errorColor,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: AppTheme.body(
                color: _errorColor,
                size: 12.5,
              ).copyWith(height: 1.35, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  static const _errorColor = Color(0xFFC62828);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAdminEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_adminPasswordKey);
      final email = prefs.getString(_adminEmailKey);
      if (!mounted) return;
      if (email != null) _emailController.text = email;
    } catch (_) {
      // Non-fatal — fields just stay empty, same as a first-ever visit.
    }
  }

  Future<void> _saveAdminEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_adminEmailKey, email);
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
    setState(() {
      _loading = true;
      _loginError = null;
    });
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

    // Password login is paused for this email (5 wrong passwords in a row),
    // or Firebase Authentication is rate-limiting — see AuthService.logIn.
    final locked =
        error != null && error.startsWith(AuthService.loginLockedPrefix);
    if (locked || error == AuthService.loginRateLimitedSentinel) {
      if (_isAdmin) {
        AuditLogService.logPreAuth(
          AuditAction.loginFailed,
          email: email,
          details: 'Too many login attempts.',
        );
      }
      setState(() => _loading = false);
      await showLoginLockoutDialog(
        context,
        waitSeconds: locked
            ? int.tryParse(
                error.substring(AuthService.loginLockedPrefix.length),
              )
            : null,
        onForgotPassword: _openForgotPassword,
      );
      return;
    }

    if (error != null) {
      // Only the admin login door is audited — the mobile farmer/buyer
      // doors share this same widget but aren't in scope for the Admin
      // Portal's audit trail (see AuditLogService).
      if (_isAdmin) {
        AuditLogService.logPreAuth(
          AuditAction.loginFailed,
          email: email,
          details: error,
        );
      }
      // Only the "N attempts remaining" warning (3rd and 4th wrong
      // password) goes under the Password field. Every other error,
      // including a plain "Incorrect email or password.", is the usual
      // pop-up at the bottom — never both at once.
      final attemptsWarning =
          error.startsWith(AuthService.wrongCredentialsMessage) &&
          error != AuthService.wrongCredentialsMessage;
      setState(() {
        _loading = false;
        if (attemptsWarning) _loginError = error;
      });
      if (!attemptsWarning) _showMessage(error);
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
        // One active Admin session at a time: asks first when the account
        // is in use on another device, then makes this one the session.
        if (!await _claimAdminSession(uid!)) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        if (!mounted) return;
        AuditLogService.log(
          AuditAction.loginSuccess,
          'Logged in to the Admin Portal.',
        );
        _saveAdminEmail(email);
        // First sign-in after a confirmed Change Email — bring the
        // Firestore copy of the email in line (a no-op otherwise).
        _authService.syncProfileEmail();
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
      // What "Create one" on this phone is checked against.
      RegistrationGuard.remember(email);
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

  // The Admin Portal allows one active session per Admin account (see
  // AdminSessionService). If the account is in use on another device the
  // Admin is asked first; Cancel signs this device back out and stays on
  // the login page. False when the sign-in was cancelled.
  //
  // The account is never locked by this, and a session record that cannot
  // be read does not keep the Admin out.
  Future<bool> _claimAdminSession(String uid) async {
    Map<String, dynamic>? record;
    try {
      record = await AdminSessionService.readRecord(uid);
    } catch (_) {
      record = null;
    }
    final localId = await AdminSessionService.localId(uid);
    if (!mounted) return false;
    if (adminSessionActiveElsewhere(record, localId, now: DateTime.now())) {
      final proceed = await showAdminSessionConflictDialog(context);
      if (!proceed) {
        await _authService.signOut(
          reason: 'admin login cancelled: account active on another device',
        );
        return false;
      }
    }
    await AdminSessionService.start(uid);
    return true;
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
        _showMessage(
          result.message ?? 'Google login failed. Please try again.',
        );
        return;

      case GoogleSignInOutcome.needsProfile:
        // The admin door has no sign-up: a Google account with no
        // users/{uid} doc can't be an admin, so it's blocked (and signed
        // back out) the same way a farmer/buyer account is.
        if (_isAdmin) {
          AuditLogService.logPreAuth(
            AuditAction.loginFailed,
            email: result.email ?? '',
            details: 'Google login: $_noAdminAccessMessage',
          );
          setState(() => _googleLoading = false);
          await applyAuthRouteResult(
            context,
            const AuthRouteResult(
              decision: AuthRouteDecision.blockedNonAdminOnWeb,
              message: _noAdminAccessMessage,
            ),
          );
          return;
        }
        setState(() => _googleLoading = false);
        Navigator.push(
          context,
          slideRoute(
            GoogleCompleteProfileScreen(
              uid: result.uid!,
              email: result.email ?? '',
              initialName: result.displayName,
              initialPhotoUrl: result.photoUrl,
              initialRole: widget.role ?? 'buyer',
            ),
          ),
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
          await _authService.signOut(
            reason:
                'Google login role mismatch: account is '
                '${routeResult.role}, door is ${widget.role}',
          );
          if (!mounted) return;
          showRoleMismatchDialog(context, routeResult.role!);
          return;
        }

        // Google authentication succeeding isn't enough for the admin
        // door — routeResult (users/{uid}.role) still decides, and only
        // role == 'admin' reaches the dashboard. Audited like the
        // password path.
        if (_isAdmin) {
          if (routeResult.decision == AuthRouteDecision.adminDashboard) {
            if (!await _claimAdminSession(result.uid!)) {
              if (mounted) setState(() => _googleLoading = false);
              return;
            }
            if (!mounted) return;
            AuditLogService.log(
              AuditAction.loginSuccess,
              'Logged in to the Admin Portal with Google.',
            );
          } else {
            AuditLogService.logPreAuth(
              AuditAction.loginFailed,
              email: _authService.currentEmail ?? '',
              details:
                  'Google login: ${routeResult.message ?? _noAdminAccessMessage}',
            );
          }
        }

        final role = routeResult.role;
        if (routeResult.isSignedIn && (role == 'farmer' || role == 'buyer')) {
          RegistrationGuard.remember(_authService.currentEmail ?? '');
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openForgotPassword() {
    final inPlace = widget.onForgotPassword;
    if (inPlace != null) {
      inPlace(_emailController.text.trim());
      return;
    }
    Navigator.push(
      context,
      slideRoute(
        ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
          isAdmin: _isAdmin,
        ),
      ),
    );
  }

  // ---- Admin Portal (web) form ----
  // Same controllers and the same _login flow as the mobile form below,
  // and the same pill-shaped controls (the fields are the shared
  // GlowField) — only the copy and sizing differ, for a desktop panel.
  // Email and password only: the Admin door has no Google sign-in.
  static const _adminMuted = Color(0xFF6B7468);
  // One height for both fields and the button, so the controls line up as
  // a single column of identical pills.
  static const _adminHeight = 58.0;

  Widget _adminLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF2B332A),
    ),
  );

  Widget _buildAdminForm() {
    const spinner = SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    const buttonShape = StadiumBorder();

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _adminLabel('Email Address'),
          const SizedBox(height: 8),
          SizedBox(
            height: _adminHeight,
            child: GlowField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              hint: 'admin@example.com',
              icon: Icons.email_outlined,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _adminLabel('Password'),
              TextButton(
                onPressed: _openForgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.mid,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _adminHeight,
            child: GlowField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              hint: 'Enter your password',
              icon: Icons.lock_outline,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _loading ? null : _login(),
              autofillHints: const [AutofillHints.password],
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          _loginErrorText(),
          const SizedBox(height: 24),
          SizedBox(
            height: _adminHeight,
            child: ElevatedButton(
              onPressed: (_loading || _googleLoading) ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.dark.withValues(alpha: 0.6),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: buttonShape,
              ),
              child: _loading
                  ? spinner
                  : Text('Login', style: AppTheme.buttonText()),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 15, color: _adminMuted),
              const SizedBox(width: 6),
              Text(
                'Authorized administrators only',
                style: TextStyle(fontSize: 12, color: _adminMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdmin) return _buildAdminForm();
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context)!.emailAddress,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
              Text(
                AppLocalizations.of(context)!.password,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: _openForgotPassword,
                child: Text(
                  AppLocalizations.of(context)!.forgotPassword,
                  style: const TextStyle(
                    color: AppTheme.dark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          _loginErrorText(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
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
                      AppLocalizations.of(context)!.loginButton,
                      style: AppTheme.buttonText(),
                    ),
            ),
          ),
          // The admin door never reaches here — it has its own layout, see
          // _buildAdminForm.
          if (!_isAdmin) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (_loading || _googleLoading)
                    ? null
                    : _continueWithGoogle,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _googleLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/images/google_logo.svg',
                            width: 19,
                            height: 19,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
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
