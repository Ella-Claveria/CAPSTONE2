import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/session_prefs_service.dart';
import '../theme/app_theme.dart';
import '../screen/admin_dashboard_screen.dart';
import '../screen/farmer_home_screen.dart';
import '../screen/buyer_marketplace_screen.dart';
import '../screen/forgot_password_screen.dart';
import '../screen/page_transitions.dart';
import 'role_mismatch_dialog.dart';
import '../l10n/app_localizations.dart';

/// The email/password sign-in form — fields, "Save login info", Forgot
/// Password, and the submit button — plus the whole sign-in flow behind it.
/// Shared by [LoginScreen] (its own door, used for saved-account switches
/// and role-specific logins) and the entry screen (embedded inline, right
/// under the logo, over the background photo) so both stay in sync instead
/// of drifting apart across edits.
class LoginFormFields extends StatefulWidget {
  // Null means "role-agnostic" login: whoever this account belongs to
  // (farmer or buyer), log them in and route them to the right home screen.
  final String? role;

  // Ready-to-go email — e.g. arriving from a saved-account tile.
  final String? initialEmail;

  const LoginFormFields({super.key, this.role, this.initialEmail});

  @override
  State<LoginFormFields> createState() => _LoginFormFieldsState();
}

class _LoginFormFieldsState extends State<LoginFormFields> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _sessionPrefs = SessionPrefsService();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _saveLoginInfo = true;

  bool get _isAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _prefillSavedEmail();
  }

  // A specific saved account always wins. Otherwise, on the role-specific
  // door, only pre-fill if this device's last login was for that same
  // role — on the generic door there's no role to match against, so any
  // remembered email is fair game.
  Future<void> _prefillSavedEmail() async {
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
      return;
    }
    if (widget.role != null) {
      final lastRole = await _sessionPrefs.getLastRole();
      if (lastRole != widget.role) return;
    }
    final email = await _sessionPrefs.getLastEmail();
    if (email == null || !mounted) return;
    _emailController.text = email;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _lookUpMyRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return doc.data()?['role'] as String?;
    } catch (_) {
      return null;
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
      expectedRole: widget.role,
    );
    if (!mounted) return;

    if (error != null && error.startsWith('ROLE_MISMATCH:')) {
      setState(() => _loading = false);
      final registeredRole = error.substring('ROLE_MISMATCH:'.length);
      showRoleMismatchDialog(context, registeredRole);
      return;
    }

    if (error != null) {
      setState(() => _loading = false);
      _showMessage(error);
      return;
    }

    // Logged in successfully, so this is definitely a registered user —
    // "save login info" only ever writes anything from this point on.
    final role = widget.role ?? await _lookUpMyRole();
    if (!mounted) return;

    if (role != 'admin') {
      if (_saveLoginInfo) {
        await _sessionPrefs.saveLastLogin(role: role ?? '', email: email);
      } else {
        // Forget just this account, not every other saved one.
        await _sessionPrefs.removeSavedAccount(email);
      }
    }

    // Logging in (as opposed to just having registered) means this is an
    // existing account, not a first-time user — so the feature walkthrough
    // on their home screen should never trigger, even on a device that
    // hasn't seen it yet (a new phone, a reinstall, a cleared app). A brand
    // new registrant never passes through here on their way to their home
    // screen (register → verify → [approval] → home), so this can't
    // accidentally suppress a genuinely new user's first-time tour.
    if (role == 'farmer' || role == 'buyer') {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('walkthrough_seen_$role', true);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loading = false);
    // pushAndRemoveUntil clears splash/role-selection/login from the stack,
    // so the back button on Home has nothing left to pop to.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) {
          if (role == 'admin') return AdminDashboardScreen();
          if (role == 'farmer') return FarmerHomeScreen();
          return const BuyerMarketplaceScreen();
        },
      ),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(AppLocalizations.of(context)!.emailAddress, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'you@example.com',
            filled: true,
            fillColor: const Color(0xFFF2F2F2),
            suffixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(AppLocalizations.of(context)!.password, style: const TextStyle(fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                slideRoute(ForgotPasswordScreen(initialEmail: _emailController.text.trim())),
              ),
              child: Text(AppLocalizations.of(context)!.forgotPassword, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Password',
            filled: true,
            fillColor: const Color(0xFFF2F2F2),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          ),
        ),
        if (!_isAdmin) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _saveLoginInfo = !_saveLoginInfo),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _saveLoginInfo,
                    activeColor: AppTheme.dark,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _saveLoginInfo = v ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.saveLoginInfo, style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _login,
            style: AppTheme.primaryButton(),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(AppLocalizations.of(context)!.loginButton, style: AppTheme.buttonText()),
          ),
        ),
      ],
    );
  }
}
