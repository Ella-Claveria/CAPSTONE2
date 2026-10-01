import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'email_verification_screen.dart';
import '../services/connectivity_service.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/glow_field.dart';
import '../widgets/permission_rationale_dialog.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';
import 'privacy_policy_screen.dart';
import 'supported_products_screen.dart';
import 'terms_and_conditions_screen.dart';

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
  const RegisterScreen({super.key, this.initialRole = 'buyer', this.initialEmail});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ---------- What the user types ----------
  final _fullNameController = TextEditingController();
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');
  // Holds only the 10 local digits (e.g. "9123456789") — the fixed "+63 "
  // prefix is display-only (see GlowField's prefixText), never part of what
  // the user types or what's stored in this controller. Required for
  // farmers (order/delivery/pick-up coordination); optional for buyers, who
  // can also give it later per-order (see place_order_screen.dart's own
  // Contact Number field).
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Barangay applies to both roles now; the certificate is farmer-only.
  String? _selectedBarangay;
  XFile? _certFile;        // the picked certificate (uploaded on submit)
  Uint8List? _certBytes;   // preview of the certificate

  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  final _imagePicker = ImagePicker();

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

  // This form is the only one long enough to scroll, so the floating back
  // arrow only gets its translucent backdrop once content is actually
  // passing underneath it — at the very top it sits directly on the plain
  // background and doesn't need one.
  final _scrollController = ScrollController();
  bool _scrolledDown = false;

  // Whether we've already explained why we need photo-library access, the
  // first time they tap to attach their certificate.
  bool _photoPromptShown = false;

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

    _scrollController.addListener(_onScroll);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  void _onChange() => setState(() {});

  void _onScroll() {
    final scrolled = _scrollController.offset > 4;
    if (scrolled != _scrolledDown) {
      setState(() => _scrolledDown = scrolled);
    }
  }

  void _selectRole(String role) {
    if (role == _selectedRole) return;
    setState(() {
      _selectedRole = role;
      // Farmer's barangay and buyer's map pin are separate fields (see the
      // LOCATION section below), so nothing needs clearing there when
      // switching — only the certificate is farmer-only.
      if (role != 'farmer') {
        _certFile = null;
        _certBytes = null;
      }
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _animController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================================
  // LIVE VALIDATION
  // ==========================================================
  bool _hasUppercase(String p) => RegExp(r'[A-Z]').hasMatch(p);
  bool _hasLowercase(String p) => RegExp(r'[a-z]').hasMatch(p);
  bool _hasNumber(String p) => RegExp(r'[0-9]').hasMatch(p);
  bool _hasSymbol(String p) => RegExp(r'''[!@#$%^&*(),.?":{}|<>_+\-=\[\]]''').hasMatch(p);

  bool _passwordMeetsRules(String p) =>
      p.length >= 12 &&
      _hasUppercase(p) &&
      _hasLowercase(p) &&
      _hasNumber(p) &&
      _hasSymbol(p);

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
    if (!_emailPattern.hasMatch(email)) return 'Please enter a valid email address.';
    return null;
  }

  bool _mobileNumberValid(String digits) => digits.length == 10 && digits.startsWith('9');

  // The "+63 " prefix is fixed/display-only (see GlowField's prefixText) —
  // the controller only ever holds the 10 local digits, and inputFormatters
  // on the field itself already reject anything but digits and cap the
  // length at 10, so there's no separate "no special characters" check
  // needed here. "Must start with 9" shows live (useful the moment they
  // type a wrong first digit); "required"/"incomplete" only after a submit
  // attempt, so mid-typing never looks like an error.
  String? get _mobileError {
    final digits = _mobileController.text.trim();
    if (digits.isEmpty) {
      if (_isFarmer && _triedSubmit) return 'Mobile number is required.';
      return null;
    }
    if (!digits.startsWith('9')) return 'Mobile number must start with 9.';
    if (digits.length != 10 && _triedSubmit) return 'Enter all 10 digits.';
    return null;
  }

  // Shown only after a submit attempt — the live checklist under the
  // password field (_passwordRequirements) already gives per-rule feedback
  // while typing, so this would be redundant noise before they've tried to
  // submit.
  String? get _passwordError {
    if (!_triedSubmit) return null;
    final p = _passwordController.text;
    if (!_passwordMeetsRules(p)) return 'Password must meet all the requirements above.';
    return null;
  }

  String? get _confirmError {
    final c = _confirmController.text;
    if (c.isEmpty) return null;
    if (c != _passwordController.text) return "Passwords don't match.";
    return null;
  }

  bool get _isFormValid {
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final mobile = _mobileController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.length < 3) return false;
    if (_nameHasDigits(name)) return false;
    if (!_emailPattern.hasMatch(email)) return false;
    if (_isFarmer) {
      // Required for farmers — order/delivery/pick-up coordination.
      if (!_mobileNumberValid(mobile)) return false;
    } else if (mobile.isNotEmpty && !_mobileNumberValid(mobile)) {
      // Optional for buyers, but whatever they typed must still be valid.
      return false;
    }
    if (!_passwordMeetsRules(pass)) return false;
    if (confirm.isEmpty || confirm != pass) return false;

    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (_certFile == null) return false;
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

    // ---- Step 2: farmers only — upload the certificate now (Cloudinary,
    // not Firestore), so its URL can travel with the rest of the profile
    // to be written post-verification.
    String? certUrl;
    if (_isFarmer && uid != null && _certFile != null) {
      certUrl = await _cloudinaryService.uploadImage(
        _certFile!,
        folder: 'agritrade/certificates',
      );
      if (!mounted) return;
      if (certUrl == null) {
        setState(() => _loading = false);
        _showMessage('Certificate upload failed. Please try again.');
        return;
      }
    }
    // Buyers no longer set a location at registration — they set it later,
    // per order, when placing one (see place_order_screen.dart).

    final mobileDigits = _mobileController.text.trim();
    final pendingProfile = PendingRegistrationProfile(
      role: _selectedRole,
      fullName: _fullNameController.text.trim(),
      mobileNumber: mobileDigits.isEmpty ? null : '+63$mobileDigits',
      supportedProductsAcknowledged: _isFarmer && _supportedProductsAcknowledged,
      barangay: _isFarmer ? _selectedBarangay : null,
      certificateUrl: certUrl,
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
      slideRoute(EmailVerificationScreen(
        role: _selectedRole,
        email: _emailController.text.trim(),
        pendingProfile: pendingProfile,
      )),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ==========================================================
  // Certificate picker
  // ==========================================================
  static const int _maxCertBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> _allowedCertExtensions = ['.png', '.jpg', '.jpeg'];

  Future<void> _pickCertificate() async {
    // Explain why before the OS photo-library prompt appears, instead of
    // surprising them with a permission dialog the moment they tap this.
    if (!_photoPromptShown) {
      _photoPromptShown = true;
      final proceed = await showPermissionRationale(
        context,
        icon: Icons.photo_library_outlined,
        title: 'Attach your certificate',
        message: 'AgriTrade+ needs access to your photos so you can attach '
            'a picture of your agricultural certification.',
      );
      if (!proceed) return;
      if (!mounted) return;
    }

    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 75,
    );
    if (picked == null) return;

    final name = picked.name.toLowerCase();
    if (!_allowedCertExtensions.any(name.endsWith)) {
      _showMessage('Please attach a PNG or JPG image.');
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxCertBytes) {
      _showMessage('That image is too large. Please attach one under 5MB.');
      return;
    }

    setState(() {
      _certFile = picked;
      _certBytes = bytes;
    });
  }

  void _removeCertificate() {
    setState(() {
      _certFile = null;
      _certBytes = null;
    });
  }

  // ==========================================================
  // Role toggle — the default is Buyer; switching to Farmer reveals the
  // verification fields below without leaving this page.
  // ==========================================================
  Widget _roleToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _roleToggleOption('buyer', AppLocalizations.of(context)!.roleBuyer, Icons.shopping_cart_outlined)),
          Expanded(child: _roleToggleOption('farmer', AppLocalizations.of(context)!.roleFarmer, Icons.agriculture_outlined)),
        ],
      ),
    );
  }

  Widget _roleToggleOption(String role, String label, IconData icon) {
    final selected = _selectedRole == role;
    return GestureDetector(
      onTap: () => _selectRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.dark : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? Colors.white : Colors.black54),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.body(color: selected ? Colors.white : Colors.black87, size: 14)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

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
                child: Text(errorText, style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
              ),
            ],
          ),
        ],
        if (errorText == null && caption != null) ...[
          const SizedBox(height: 6),
          Text(caption, style: TextStyle(color: Colors.grey[600], fontSize: 11.5)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ==========================================================
  // Live password requirements — hidden until they start typing a
  // password, then each item turns green the moment it's satisfied.
  // ==========================================================
  Widget _passwordRequirements() {
    final p = _passwordController.text;
    if (p.isEmpty) return const SizedBox(height: 16);

    final requirements = <(String, bool)>[
      ('12+ characters', p.length >= 12),
      ('Uppercase letter', _hasUppercase(p)),
      ('Lowercase letter', _hasLowercase(p)),
      ('Number', _hasNumber(p)),
      ('Symbol', _hasSymbol(p)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: requirements.map((req) {
          final (label, met) = req;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                met ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: met ? Colors.green[600] : Colors.grey[400],
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: met ? FontWeight.w600 : FontWeight.normal,
                  color: met ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ==========================================================
  // A heads-up before the farmer-only fields: this app only approves
  // farmers within Laurel, Batangas (the barangay list below is scoped to
  // it), so anyone outside that area shouldn't expect to get verified.
  // ==========================================================
  Widget _laurelNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only verified farmers from Laurel, Batangas will be approved.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // Farmer supported-product awareness — a farmer must know the
  // marketplace scope before they ever try to list something, but the
  // full explanation is too long to sit inline in an already-long form.
  // So the form itself only shows this one-line banner; tapping it opens
  // _showSupportedProductsSheet with the full explanation, the "View
  // Supported Products" link, and the acknowledgment checkbox itself —
  // required and never pre-checked, same as before. Its state is stored
  // on the account via AuthService.signUp's supportedProductsAcknowledged
  // field.
  // ==========================================================
  Widget _supportedProductsSection() {
    final showError = _triedSubmit && !_supportedProductsAcknowledged;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showSupportedProductsSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: showError ? Colors.red : AppTheme.mid, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(
                    _supportedProductsAcknowledged ? Icons.check_circle : Icons.eco_outlined,
                    color: _supportedProductsAcknowledged ? Colors.green[700] : AppTheme.dark,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _supportedProductsAcknowledged
                          ? 'Supported Products reviewed'
                          : 'Supported Products apply — tap to review',
                      style: AppTheme.body(color: AppTheme.dark, size: 13).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.mid),
                ],
              ),
            ),
          ),
          if (showError) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text('Please review and confirm the supported products scope.',
                      style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showSupportedProductsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.eco_outlined, color: AppTheme.dark, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Supported Products in AgriTrade+',
                            style: AppTheme.body(color: AppTheme.dark, size: 14.5).copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AgriTrade+ currently supports selected agricultural commodities based on '
                    'the products identified with the agricultural office. Only supported '
                    'products can be posted in the marketplace.',
                    style: AppTheme.body(color: Colors.black87, size: 13).copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportedProductsScreen()),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.dark,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('View Supported Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => setSheetState(
                        () => _supportedProductsAcknowledged = !_supportedProductsAcknowledged),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _supportedProductsAcknowledged,
                          onChanged: (v) => setSheetState(() => _supportedProductsAcknowledged = v ?? false),
                          activeColor: AppTheme.dark,
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I understand that AgriTrade+ currently supports only selected '
                              'agricultural commodities and that I can only post products '
                              'included in the Supported Products list.',
                              style: AppTheme.body(color: Colors.black87, size: 12.5).copyWith(height: 1.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: AppTheme.primaryButton(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mid.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_outlined, color: AppTheme.mid, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Public Location Preview',
                    style: AppTheme.body(color: Colors.black87, size: 12.5).copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Buyers will see:', style: AppTheme.body(color: Colors.black54, size: 11.5)),
                const SizedBox(height: 2),
                Text('$_selectedBarangay, Laurel, Batangas',
                    style: AppTheme.body(color: AppTheme.dark, size: 13).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Your exact coordinates will not be displayed publicly.',
                    style: AppTheme.body(color: Colors.black45, size: 11)),
              ],
            ),
          ),
        ],
      ),
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
                        style: AppTheme.body(color: Colors.black87, size: 12.5).copyWith(height: 1.4),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: AppTheme.body(color: AppTheme.dark, size: 12.5)
                                .copyWith(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()),
                                  ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: AppTheme.body(color: AppTheme.dark, size: 12.5)
                                .copyWith(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                                  ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    if (showError)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Please accept the Terms & Conditions and Privacy Policy to continue.',
                            style: TextStyle(color: Colors.red, fontSize: 11.5)),
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
  // Certificate attach box
  // ==========================================================
  Widget _buildCertificatePicker() {
    final showError = _triedSubmit && _certFile == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Agricultural Certification', style: AppTheme.label()),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _loading ? null : _pickCertificate,
          child: Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: showError ? Colors.red : AppTheme.mid,
                width: 1.2,
              ),
            ),
            child: _certBytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.upload_file,
                          size: 38, color: AppTheme.mid),
                      const SizedBox(height: 8),
                      Text('Attach your certificate',
                          style: AppTheme.body(size: 13)),
                      const SizedBox(height: 2),
                      Text('PNG or JPG only, up to 5MB',
                          style: AppTheme.body(
                              color: Colors.black45, size: 11.5)),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(_certBytes!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                            onPressed: _loading ? null : _removeCertificate,
                            tooltip: 'Remove',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Text('Agricultural certification is required.',
              style: TextStyle(color: Colors.red, fontSize: 11.5)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isFormValid && !_loading;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 64, 24, 12),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          // ---- Logo ----
                          Center(
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 70,
                              height: 70,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 70,
                                  height: 70,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.mid,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.agriculture,
                                      size: 38, color: Colors.white),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),

                          const Center(child: AgriTradeText(fontSize: 26)),
                          const SizedBox(height: 6),
                          Center(
                            child: Text(AppLocalizations.of(context)!.registerTitle,
                                style: AppTheme.heading(20)),
                          ),
                          const SizedBox(height: 20),

                          // ---- Role toggle (defaults to Buyer) ----
                          Text('I am a...', style: AppTheme.label()),
                          const SizedBox(height: 8),
                          _roleToggle(),
                          const SizedBox(height: 20),

                          // ---- Full name ----
                          _buildField(
                            label: AppLocalizations.of(context)!.fullName,
                            controller: _fullNameController,
                            hint: 'Juan F. Santos',
                            icon: Icons.person_outline,
                            errorText: _nameError,
                          ),

                          // ---- Email ----
                          _buildField(
                            label: AppLocalizations.of(context)!.emailAddress,
                            controller: _emailController,
                            hint: 'juansantos@gmail.com',
                            icon: Icons.email_outlined,
                            keyboard: TextInputType.emailAddress,
                            errorText: _emailError,
                          ),

                          // ---- Mobile Number ----
                          // Required for farmers (order/delivery/pick-up
                          // coordination); optional for buyers, who can also
                          // give it later per order instead. Fixed +63
                          // prefix — no country dropdown, PH-only scope.
                          _buildField(
                            label: _isFarmer ? 'Mobile Number' : 'Mobile Number (optional)',
                            controller: _mobileController,
                            hint: '912 345 6789',
                            icon: Icons.phone_outlined,
                            keyboard: TextInputType.phone,
                            prefixText: '+63 ',
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            errorText: _mobileError,
                            caption: _isFarmer
                                ? 'For order, delivery, and pick-up coordination only.'
                                : null,
                          ),

                          // ---- Password ----
                          _buildField(
                            label: AppLocalizations.of(context)!.password,
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
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          _passwordRequirements(),

                          // ---- Confirm password ----
                          _buildField(
                            label: AppLocalizations.of(context)!.confirmPassword,
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
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),

                          // ================================================
                          // LOCATION — farmers only (BarangayLocationField,
                          // for verification), restricted to Laurel. Buyers
                          // no longer set a location at registration at
                          // all — they set it later, per order, when
                          // placing one (see place_order_screen.dart).
                          // The certificate stays farmer-only below.
                          // ================================================
                          if (_isFarmer) ...[
                            const Divider(height: 8),
                            const SizedBox(height: 14),
                            _laurelNotice(),
                            const SizedBox(height: 14),
                            _supportedProductsSection(),
                            BarangayLocationField(
                              value: _selectedBarangay,
                              errorText: _triedSubmit && _selectedBarangay == null
                                  ? 'Please select a barangay in Laurel.'
                                  : null,
                              onChanged: (value) => setState(() => _selectedBarangay = value),
                            ),
                            _publicLocationPreview(),
                            _buildCertificatePicker(),
                          ],
                          const SizedBox(height: 4),
                          _consentCheckbox(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ---- Register button, floating above the scrollable form so ----
            // ---- it's always reachable no matter how long the form gets ----
            // ---- (e.g. once the farmer fields are showing) — plus the   ----
            // ---- log-in link, both pinned to the bottom of the screen.  ----
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: BoxDecoration(
                color: AppTheme.bgLight,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canSubmit ? _register : null,
                      style: AppTheme.primaryButton(),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(AppLocalizations.of(context)!.registerButton, style: AppTheme.buttonText()),
                    ),
                  ),
                  // Gentle hint when the button is disabled.
                  if (!_isFormValid && !_loading) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Please complete all fields first.',
                      style: AppTheme.body(color: Colors.black45, size: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: RichText(
                      text: TextSpan(
                        style: AppTheme.body(color: Colors.black87, size: 13.5),
                        children: [
                          TextSpan(text: AppLocalizations.of(context)!.alreadyHaveAccount),
                          TextSpan(
                            text: AppLocalizations.of(context)!.logIn,
                            style: AppTheme.body(color: AppTheme.dark, size: 13.5)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),

            // ---- Back arrow, floating above everything at the top-left ----
            // ---- corner — not part of the card, so it stays visible    ----
            // ---- no matter how far the form is scrolled. Only gets its ----
            // ---- translucent backdrop once the card has actually       ----
            // ---- scrolled underneath it — at rest it sits on the plain ----
            // ---- background and doesn't need one.                     ----
            Positioned(
              top: 4,
              left: 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _scrolledDown ? Colors.white.withValues(alpha: 0.7) : Colors.transparent,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.dark),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

