import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/ph_mobile.dart';
import '../services/registration_guard.dart';
import '../widgets/existing_account_dialog.dart';
import 'login_screen.dart';
import '../services/rsba_number.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/app_back_button.dart';
import 'email_verification_screen.dart';
import '../services/connectivity_service.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/glow_field.dart';
import '../widgets/password_requirements.dart';
import '../widgets/public_location_preview.dart';
import '../widgets/role_toggle.dart';
import 'page_transitions.dart';
import 'privacy_policy_screen.dart';
import 'supported_products_screen.dart';
import 'terms_and_conditions_screen.dart';
import '../l10n/tr.dart';

class RegisterScreen extends StatefulWidget {
  // Which role the toggle at the top starts on. Defaults to buyer; the
  // "remembered last login" flow passes whichever role that device last
  // used, but the toggle is always live — the user can switch it right
  // there on the form and the fields below adjust accordingly.
  final String initialRole;
  // Pre-fills the Email field — used by the login form's "Email not
  // registered? Create One" prompt, so the email they already typed there
  // doesn't need to be retyped.
  final String? initialEmail;
  const RegisterScreen({
    super.key,
    this.initialRole = 'buyer',
    this.initialEmail,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ---------- What the user types ----------
  final _fullNameController = TextEditingController();
  late final _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  // Holds only the 10 local digits (e.g. "9123456789") — the fixed "+63 "
  // prefix is display-only (see GlowField's prefixText), never part of what
  // the user types or what's stored in this controller. Required for both
  // roles: it is how a buyer and a farmer reach each other about an order
  // (see place_order_screen.dart, which starts from this number). A valid
  // format is all that is checked — the number is never treated as
  // verified.
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Farmer-only: the barangay and the RSBA number (see rsba_number.dart).
  // The number is kept while the role toggle is on Buyer, so switching
  // back to Farmer does not lose what was typed.
  String? _selectedBarangay;
  final _rsbaController = TextEditingController();
  // Set once the RSBA field has been left with something in it — only
  // then is a number that is not valid shown as an error.
  bool _rsbaTouched = false;

  // Created on first use (Register), not with the screen.
  late final _authService = AuthService();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _triedSubmit = false; // becomes true once they tap Sign Up

  // Registration consent (Terms & Conditions / Privacy Policy) — required
  // for both roles, never pre-checked. Farmer-only supported-product
  // acknowledgment is separate, since it's specific to Farmer setup.
  bool _agreedToTerms = false;
  bool _supportedProductsAcknowledged = false;

  late String _selectedRole = widget.initialRole;

  // The form scrolls under the floating Back button (see build).
  final _scrollController = ScrollController();

  // ---------- Floating Register button ----------
  // The button floats at the bottom of the screen while the form is longer
  // than the screen, and settles into its own place at the end of the form
  // (an empty gap of the same height, above the hint and the log-in link)
  // once that place scrolls into view — see _registerButtonBottom.
  static const double _registerButtonHeight = 52;
  static const double _registerFloatGap = 6;
  // Everything under the button's place: the hint and the log-in link
  // (_formEnd gives them this fixed height), then the form's own bottom
  // padding. Fixed, so where the button rests is known from the scroll
  // position alone. Just tall enough for both lines at the largest text
  // size allowed there (×1.3), so no empty band is left under them.
  static const double _formEndTextHeight = 62;
  static const double _formBottomPadding = 8;
  // Where the button was last drawn; see the check at the top of build.
  double _drawnRegisterBottom = _registerFloatGap;

  // ---------- Entrance animation, matching the splash ----------
  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  // Only Gmail addresses are accepted for registration.
  final _emailPattern = RegExp(r'^[\w\.\-]+@gmail\.com$', caseSensitive: false);

  bool get _isFarmer => _selectedRole == 'farmer';

  @override
  void initState() {
    super.initState();

    // Rebuild on every keystroke so errors + the button update live.
    _fullNameController.addListener(_onChange);
    _emailController.addListener(_onChange);
    _mobileController.addListener(_onChange);
    _passwordController.addListener(_onChange);
    _confirmController.addListener(_onChange);
    _rsbaController.addListener(_onChange);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  // How far above the bottom of the screen area the Register button sits:
  // floating just above the edge, or — once its place at the end of the
  // form has scrolled up into view — resting in that place. With the
  // keyboard open it always stays in its place in the form, so it never
  // covers the field being typed in.
  double _registerButtonBottom(bool keyboardOpen) {
    if (!_scrollController.hasClients) return _registerFloatGap;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return _registerFloatGap;
    final leftToScroll = position.maxScrollExtent - position.pixels;
    final inPlace = _formEndTextHeight + _formBottomPadding - leftToScroll;
    return keyboardOpen ? inPlace : math.max(_registerFloatGap, inPlace);
  }

  void _onChange() => setState(() {});

  void _selectRole(String role) {
    if (role == _selectedRole) return;
    setState(() {
      _selectedRole = role;
      // Nothing typed is cleared: the farmer-only fields are just hidden
      // for a buyer, and are never sent with a buyer registration.
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _rsbaController.dispose();
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================================
  // LIVE VALIDATION
  // ==========================================================
  // The shared rules (password_requirements.dart), also used by Change
  // Password.
  bool _passwordMeetsRules(String p) => PasswordRules.meetsAll(p);

  bool _nameHasDigits(String name) => RegExp(r'[0-9]').hasMatch(name);

  String? get _nameError {
    final name = _fullNameController.text.trim();
    if (name.isEmpty) return null;
    if (name.length < 3) return 'That name looks too short.';
    if (_nameHasDigits(name)) return 'Full name cannot contain numbers.';
    return null;
  }

  String? get _emailError {
    final email = _emailController.text.trim();
    if (email.isEmpty) return null;
    if (!_emailPattern.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  bool _mobileNumberValid(String digits) => isValidPhMobile(digits);

  // The "+63 " prefix is fixed/display-only (see GlowField's prefixText) —
  // the controller only ever holds the 10 local digits, and inputFormatters
  // on the field itself already reject anything but digits and cap the
  // length at 10, so there's no separate "no special characters" check
  // needed here. "Must start with 9" shows live (useful the moment they
  // type a wrong first digit); "required"/"incomplete" only after a submit
  // attempt, so mid-typing never looks like an error.
  String? get _mobileError {
    // Shared rules for every mobile field in the app — see ph_mobile.dart.
    return phMobileError(
      _mobileController.text.trim(),
      required: true,
      submitted: _triedSubmit,
    );
  }

  // Shown only after a submit attempt — the live checklist under the
  // password field (_passwordRequirements) already gives per-rule feedback
  // while typing, so this would be redundant noise before they've tried to
  // submit.
  String? get _passwordError {
    if (!_triedSubmit) return null;
    final p = _passwordController.text;
    if (!_passwordMeetsRules(p)) {
      return 'Password must meet all the requirements above.';
    }
    return null;
  }

  String? get _confirmError {
    final c = _confirmController.text;
    if (c.isEmpty) return null;
    if (c != _passwordController.text) return "Passwords don't match.";
    return null;
  }

  String? get _rsbaError => rsbaError(
    _rsbaController.text,
    touched: _rsbaTouched,
    submitted: _triedSubmit,
  );

  bool get _isFormValid {
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final mobile = _mobileController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.length < 3) return false;
    if (_nameHasDigits(name)) return false;
    if (!_emailPattern.hasMatch(email)) return false;
    // Required for both roles — order/delivery/pick-up coordination.
    if (!_mobileNumberValid(mobile)) return false;
    if (!_passwordMeetsRules(pass)) return false;
    if (confirm.isEmpty || confirm != pass) return false;

    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (!isValidRsba(_rsbaController.text)) return false;
      if (!_supportedProductsAcknowledged) return false;
    }
    if (!_agreedToTerms) return false;
    return true;
  }

  // ==========================================================
  // REGISTER
  // ==========================================================
  Future<void> _register() async {
    setState(() => _triedSubmit = true);
    if (!_isFormValid) {
      _showMessage('Please fix the errors below before continuing.');
      return;
    }

    // ── Internet check ──
    if (!await hasInternet()) {
      _showMessage('No internet connection. Please check your connection.');
      return;
    }

    setState(() => _loading = true);

    // An account or a Farmer application for this email already exists:
    // say where it stands and send them to Login, rather than starting a
    // second registration. Checked by the normalized email (see
    // RegistrationGuard); nothing has been created at this point.
    final existing = await RegistrationGuard.check(_emailController.text);
    if (!mounted) return;
    if (existing != ExistingAccount.none) {
      setState(() => _loading = false);
      final choice = await showExistingAccountDialog(context, existing);
      if (!mounted) return;
      if (choice == ExistingAccountChoice.login) {
        Navigator.pushReplacement(
          context,
          slideRoute(
            LoginScreen(
              role: existing == ExistingAccount.registered
                  ? _selectedRole
                  : 'farmer',
            ),
          ),
        );
      }
      return;
    }

    // One role per account is already guaranteed by Firebase Auth itself —
    // an email can only ever back one account/uid, and a role is fixed to
    // that account at creation and immutable afterward (see firestore
    // .rules' users/{userId} update rule). signUp below surfaces
    // "email-already-in-use" if this email is already registered under
    // any role.

    // ---- Step 1: create the Firebase Auth account only — no Firestore
    // profile yet. That's written in one shot, after email verification
    // actually succeeds, by EmailVerificationScreen (see
    // AuthService.completeRegistration's doc comment for why).
    final error = await _authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() => _loading = false);
      _showMessage(error);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    // "Create one" on this phone is checked against this account from now
    // on.
    RegistrationGuard.remember(_emailController.text);

    // Buyers no longer set a location at registration — they set it later,
    // per order, when placing one (see place_order_screen.dart).

    final mobileDigits = _mobileController.text.trim();
    final pendingProfile = PendingRegistrationProfile(
      role: _selectedRole,
      fullName: _fullNameController.text.trim(),
      mobileNumber: mobileDigits.isEmpty ? null : phMobileE164(mobileDigits),
      supportedProductsAcknowledged:
          _isFarmer && _supportedProductsAcknowledged,
      barangay: _isFarmer ? _selectedBarangay : null,
      // For the admin to check — a well-formed number approves nothing.
      rsbaNumber: _isFarmer ? normalizeRsba(_rsbaController.text) : null,
    );
    // Durable (survives the app being closed while they check their
    // email), not just an in-memory navigation argument — see
    // PendingRegistrationProfile's doc comment.
    if (uid != null) await _authService.savePendingProfile(uid, pendingProfile);

    if (!mounted) return;
    setState(() => _loading = false);

    // ---- Step 3: go verify the email ----
    Navigator.pushReplacement(
      context,
      slideRoute(
        EmailVerificationScreen(
          role: _selectedRole,
          email: _emailController.text.trim(),
          pendingProfile: pendingProfile,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ==========================================================
  // Role toggle — the default is Buyer; switching to Farmer reveals the
  // verification fields below without leaving this page.
  // ==========================================================
  Widget _roleToggle() => RoleToggle(
    selected: _selectedRole,
    onChanged: _selectRole,
    buyerLabel: tr(context).roleBuyer,
    farmerLabel: tr(context).roleFarmer,
  );

  // ==========================================================
  // A reusable text field.
  // ==========================================================
  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? errorText,
    String? caption,
    bool obscure = false,
    Widget? suffix,
    String? prefixText,
    List<TextInputFormatter>? inputFormatters,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label()),
        const SizedBox(height: 8),
        GlowField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          hint: hint,
          icon: icon,
          suffix: suffix,
          prefixText: prefixText,
          inputFormatters: inputFormatters,
        ),
        // Rendered as its own line below the field, not inside it (GlowField
        // no longer accepts an errorText of its own) — keeps every field's
        // error visually outside the input itself.
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
        if (errorText == null && caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ==========================================================
  // Live password requirements — hidden until they start typing a
  // password, then each item turns green the moment it's satisfied.
  // ==========================================================
  Widget _passwordRequirements() =>
      PasswordRequirementsChecklist(password: _passwordController.text);

  // ==========================================================
  // A heads-up before the farmer-only fields: registration is only open to
  // farmers within Laurel, Batangas (the barangay list below is scoped to
  // it).
  // ==========================================================
  Widget _laurelNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only farmers from Laurel, Batangas may register.',
              style: AppTheme.body(
                color: const Color(0xFF6D4C00),
                size: 12,
              ).copyWith(fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // Farmer supported-product awareness — a farmer must know the
  // marketplace scope before they ever try to list something. A checkbox
  // right above the Terms agreement, ticked in place (required, never
  // pre-checked); "Supported Products" in its text opens the full list.
  // Its state is stored on the account via
  // AuthService.completeRegistration's supportedProductsAcknowledged field.
  // ==========================================================
  Widget _supportedProductsCheckbox() {
    final showError = _triedSubmit && !_supportedProductsAcknowledged;
    return InkWell(
      onTap: () => setState(
        () => _supportedProductsAcknowledged = !_supportedProductsAcknowledged,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _supportedProductsAcknowledged,
            onChanged: (v) =>
                setState(() => _supportedProductsAcknowledged = v ?? false),
            activeColor: AppTheme.dark,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: AppTheme.body(
                        color: Colors.black87,
                        size: 12.5,
                      ).copyWith(height: 1.4),
                      children: [
                        const TextSpan(
                          text:
                              'I understand that I can only post products '
                              'included in the ',
                        ),
                        TextSpan(
                          text: 'Supported Products',
                          style: AppTheme.body(color: AppTheme.dark, size: 12.5)
                              .copyWith(
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SupportedProductsScreen(),
                              ),
                            ),
                        ),
                        const TextSpan(text: ' list.'),
                      ],
                    ),
                  ),
                  if (showError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Please confirm the supported products scope to continue.',
                        style: TextStyle(color: Colors.red, fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // Farmer public location preview — shown once a barangay is selected, so
  // the farmer sees exactly what buyers will see before they finish
  // registering. Uses the real selected barangay (never a dummy value);
  // municipality/province are fixed since farmer registration is scoped to
  // Laurel, Batangas (see _laurelNotice above).
  // ==========================================================
  Widget _publicLocationPreview() {
    if (_selectedBarangay == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PublicLocationPreview(barangay: _selectedBarangay!),
    );
  }

  // ==========================================================
  // Registration consent — required for both roles, never pre-checked.
  // Terms & Privacy each open their own screen so they're independently
  // readable before the user agrees.
  // ==========================================================
  Widget _consentCheckbox() {
    final showError = _triedSubmit && !_agreedToTerms;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _agreedToTerms,
              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
              activeColor: AppTheme.dark,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: AppTheme.body(
                          color: Colors.black87,
                          size: 12.5,
                        ).copyWith(height: 1.4),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style:
                                AppTheme.body(
                                  color: AppTheme.dark,
                                  size: 12.5,
                                ).copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const TermsAndConditionsScreen(),
                                ),
                              ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style:
                                AppTheme.body(
                                  color: AppTheme.dark,
                                  size: 12.5,
                                ).copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    if (showError)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Please accept the Terms & Conditions and Privacy Policy to continue.',
                          style: TextStyle(color: Colors.red, fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // RSBA No. — farmers only, right after Full Name. It took the place of
  // the certificate upload.
  // The Focus wrapper only listens: once the field is left with something
  // typed in it, a number that is not valid starts showing as an error.
  // ==========================================================
  Widget _rsbaField() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus && _rsbaController.text.isNotEmpty && !_rsbaTouched) {
          setState(() => _rsbaTouched = true);
        }
      },
      child: _buildField(
        label: kRsbaLabel,
        controller: _rsbaController,
        hint: kRsbaHint,
        icon: Icons.badge_outlined,
        // Plain keyboard with letters and numbers, no autocorrect.
        keyboard: TextInputType.visiblePassword,
        inputFormatters: kRsbaInputFormatters,
        errorText: _rsbaError,
      ),
    );
  }

  // ==========================================================
  // The Register button. It is drawn once, floating over the form (see
  // build and _registerButtonBottom) — no bar or background behind it, so
  // its disabled state is a solid grey rather than a see-through one.
  // ==========================================================
  Widget _registerButton(bool canSubmit) {
    return SizedBox(
      height: _registerButtonHeight,
      child: ElevatedButton(
        onPressed: canSubmit ? _register : null,
        style: AppTheme.primaryButton().copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? const Color(0xFFDDDDDD)
                : AppTheme.dark,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? const Color(0xFF8F8F8F)
                : Colors.white,
          ),
        ),
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(tr(context).registerButton, style: AppTheme.buttonText()),
      ),
    );
  }

  // ==========================================================
  // The end of the form: the Register button's own place, then the hint
  // and the way back to Login. These scroll with the form.
  // ==========================================================
  Widget _formEnd() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // Empty on purpose — the floating button comes to rest here.
        const SizedBox(height: _registerButtonHeight, width: double.infinity),
        // A fixed height (see _formEndTextHeight), whether or not the hint
        // is showing; very large font settings are held back a little so
        // both lines always fit in it.
        SizedBox(
          height: _formEndTextHeight,
          width: double.infinity,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Gentle hint when the button is disabled.
                if (!_isFormValid && !_loading) ...[
                  Text(
                    'Please complete all fields first.',
                    style: AppTheme.body(color: Colors.black45, size: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: RichText(
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.3),
                    text: TextSpan(
                      style: AppTheme.body(color: Colors.black87, size: 13.5),
                      children: [
                        TextSpan(text: tr(context).alreadyHaveAccount),
                        TextSpan(
                          text: tr(context).logIn,
                          style: AppTheme.body(
                            color: AppTheme.dark,
                            size: 13.5,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isFormValid && !_loading;

    // The form's height changes with the role, the errors showing and the
    // keyboard — none of which is a scroll. So once this frame is laid
    // out, draw again if the button now belongs somewhere else.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottom = _registerButtonBottom(keyboardOpen);
      if ((bottom - _drawnRegisterBottom).abs() > 0.5) setState(() {});
    });

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(
                24,
                56,
                24,
                _formBottomPadding,
              ),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---- Logo ----
                      // logo.png has a wide transparent margin around the
                      // artwork: shown larger, and only the artwork's own
                      // height is kept, so the wordmark sits right under it
                      // (as on Forgot Password).
                      Align(
                        heightFactor: 0.76,
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 100,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 70,
                              height: 70,
                              decoration: const BoxDecoration(
                                color: AppTheme.mid,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.agriculture,
                                size: 38,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),

                      const Center(child: AgriTradeText(fontSize: 26)),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          tr(context).registerTitle,
                          style: AppTheme.heading(20),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- Role toggle (defaults to Buyer) ----
                      Text('Choose your role', style: AppTheme.label()),
                      const SizedBox(height: 8),
                      _roleToggle(),
                      const SizedBox(height: 20),

                      // ---- Full name ----
                      _buildField(
                        label: tr(context).fullName,
                        controller: _fullNameController,
                        hint: 'Juan F. Santos',
                        icon: Icons.person_outline,
                        errorText: _nameError,
                      ),

                      // ---- RSBA No. (farmers only) ----
                      if (_isFarmer) _rsbaField(),

                      // ---- Email ----
                      _buildField(
                        label: tr(context).emailAddress,
                        controller: _emailController,
                        hint: 'juansantos@gmail.com',
                        icon: Icons.email_outlined,
                        keyboard: TextInputType.emailAddress,
                        errorText: _emailError,
                      ),

                      // ---- Mobile Number ----
                      // Required for both roles (order/delivery/pick-up
                      // coordination). Fixed +63 prefix — no country
                      // dropdown, PH-only scope; a number typed or pasted
                      // as 09… or +639… is reduced to the same 10 digits.
                      _buildField(
                        label: 'Mobile Number',
                        controller: _mobileController,
                        hint: kPhMobileHint,
                        icon: Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        prefixText: kPhMobilePrefix,
                        inputFormatters: kPhMobileInputFormatters,
                        errorText: _mobileError,
                        caption:
                            'For order, delivery, and pick-up coordination only.',
                      ),

                      // ---- Password ----
                      _buildField(
                        label: tr(context).password,
                        controller: _passwordController,
                        hint: 'At least 12 characters',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        errorText: _passwordError,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      _passwordRequirements(),

                      // ---- Confirm password ----
                      _buildField(
                        label: tr(context).confirmPassword,
                        controller: _confirmController,
                        hint: 'Re-enter your password',
                        icon: Icons.lock_reset_outlined,
                        obscure: _obscureConfirm,
                        errorText: _confirmError,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),

                      // ================================================
                      // Farmers only — the Laurel notice, then the barangay
                      // (BarangayLocationField, restricted to Laurel), for
                      // verification. Buyers set no location at
                      // registration; they set it later, per order (see
                      // place_order_screen.dart). The supported-products
                      // checkbox sits right above the Terms agreement.
                      // ================================================
                      if (_isFarmer) ...[
                        _laurelNotice(),
                        const SizedBox(height: 16),
                        BarangayLocationField(
                          value: _selectedBarangay,
                          errorText: _triedSubmit && _selectedBarangay == null
                              ? 'Please select a barangay in Laurel.'
                              : null,
                          onChanged: (value) =>
                              setState(() => _selectedBarangay = value),
                        ),
                        _publicLocationPreview(),
                        _supportedProductsCheckbox(),
                      ],
                      const SizedBox(height: 4),
                      _consentCheckbox(),
                      _formEnd(),
                    ],
                  ),
                ),
              ),
            ),

            // ---- Register button: the only thing that floats, with    ----
            // ---- nothing behind it. It comes to rest in its own place ----
            // ---- at the end of the form (see _registerButtonBottom).  ----
            ListenableBuilder(
              listenable: _scrollController,
              builder: (context, child) {
                _drawnRegisterBottom = _registerButtonBottom(keyboardOpen);
                return Positioned(
                  left: 24,
                  right: 24,
                  bottom: _drawnRegisterBottom,
                  child: child!,
                );
              },
              child: _registerButton(canSubmit),
            ),

            // ---- Back button, floating above everything at the top-left ----
            // ---- corner, so it stays visible no matter how far the    ----
            // ---- form is scrolled.                                     ----
            const Positioned(top: 8, left: 12, child: AppBackButton()),
          ],
        ),
      ),
    );
  }
}
