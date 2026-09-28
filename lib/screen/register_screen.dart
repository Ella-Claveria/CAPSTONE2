import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../services/device_role_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'email_verification_screen.dart';
import '../services/connectivity_service.dart';
import '../services/location_permission_prompt.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/glow_field.dart';
import '../widgets/my_location_field.dart';
import '../widgets/permission_rationale_dialog.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';

class RegisterScreen extends StatefulWidget {
  // Which role the toggle at the top starts on. Defaults to buyer; the
  // "remembered last login" flow passes whichever role that device last
  // used, but the toggle is always live — the user can switch it right
  // there on the form and the fields below adjust accordingly.
  final String initialRole;
  const RegisterScreen({super.key, this.initialRole = 'buyer'});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ---------- What the user types ----------
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // Barangay applies to both roles now; the certificate is farmer-only.
  String? _selectedBarangay;
  // Only set when BarangayLocationField's "Use my location" actually got a
  // GPS fix — a manually-picked barangay leaves these null, same as how a
  // farmer's precise pin is a separate, optional step from their barangay.
  double? _pickedLat;
  double? _pickedLng;
  XFile? _certFile;        // the picked certificate (uploaded on submit)
  Uint8List? _certBytes;   // preview of the certificate

  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  final _deviceRoleService = DeviceRoleService();
  final _imagePicker = ImagePicker();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _triedSubmit = false; // becomes true once they tap Sign Up

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

  final _emailPattern = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');

  bool get _isFarmer => _selectedRole == 'farmer';

  @override
  void initState() {
    super.initState();

    // Rebuild on every keystroke so errors + the button update live.
    _fullNameController.addListener(_onChange);
    _emailController.addListener(_onChange);
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
      p.length >= 8 &&
      _hasUppercase(p) &&
      _hasLowercase(p) &&
      _hasNumber(p) &&
      _hasSymbol(p);

  String? get _nameError {
    final name = _fullNameController.text.trim();
    if (name.isEmpty) return null;
    if (name.length < 3) return 'That name looks too short.';
    return null;
  }

  String? get _emailError {
    final email = _emailController.text.trim();
    if (email.isEmpty) return null;
    if (!_emailPattern.hasMatch(email)) return "That doesn't look like a valid email.";
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
    final pass = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.length < 3) return false;
    if (!_emailPattern.hasMatch(email)) return false;
    if (!_passwordMeetsRules(pass)) return false;
    if (confirm.isEmpty || confirm != pass) return false;

    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (_certFile == null) return false;
    } else {
      if (_pickedLat == null || _pickedLng == null) return false;
    }
    return true;
  }

  // ==========================================================
  // REGISTER
  // ==========================================================
  Future<void> _register() async {
    setState(() => _triedSubmit = true);
    if (!_isFormValid) return;

    // ── Internet check ──
    if (!await hasInternet()) {
      _showMessage('No internet connection. Please check your connection.');
      return;
    }

    setState(() => _loading = true);

    // ---- Step 1: this device can only ever hold one role ----
    final registeredRole = await _deviceRoleService.getRegisteredRole();
    if (!mounted) return;
    if (registeredRole != null && registeredRole != _selectedRole) {
      setState(() => _loading = false);
      _showMessage('This device already has a $registeredRole account. '
          'Only one role is allowed per device.');
      return;
    }

    // ---- Step 2: create the account ----
    final error = await _authService.signUp(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: _selectedRole,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() => _loading = false);
      _showMessage(error);
      return;
    }

    final newUid = FirebaseAuth.instance.currentUser?.uid;
    if (newUid != null) {
      await _deviceRoleService.claimDevice(role: _selectedRole, uid: newUid);
    }

    // ---- Step 3: farmers only — upload the certificate ----
    if (_isFarmer) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && _certFile != null) {
        final certUrl = await _cloudinaryService.uploadImage(
          _certFile!,
          folder: 'agritrade/certificates',
        );

        if (!mounted) return;
        if (certUrl == null) {
          setState(() => _loading = false);
          _showMessage('Certificate upload failed. Please try again.');
          return;
        }

        final docError = await _authService.saveVerificationDocument(
          uid: uid,
          documentUrl: certUrl,
          barangay: _selectedBarangay!,
          fullName: _fullNameController.text.trim(),
        );

        if (!mounted) return;
        if (docError != null) {
          setState(() => _loading = false);
          _showMessage(docError);
          return;
        }

      }
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && _pickedLat != null && _pickedLng != null) {
        await _authService.saveBuyerLocation(
          uid: uid,
          latitude: _pickedLat!,
          longitude: _pickedLng!,
        );
      }
      // Also primes the separate, ongoing "sort nearby farms by distance"
      // permission used later in the marketplace — a no-op prompt-wise if
      // MyLocationField's "Use my location" already granted it above.
      if (mounted) {
        await maybeRequestLocationPermission(
          context,
          title: 'Find farms near you',
          message: "AgriTrade+ uses your location to show how far nearby "
              "farms are and sort them by distance. You can skip this and "
              "still browse everything.",
        );
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // ---- Step 4: go verify the email ----
    Navigator.pushReplacement(
      context,
      slideRoute(EmailVerificationScreen(
        role: _selectedRole,
        email: _emailController.text.trim(),
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
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
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
    bool obscure = false,
    Widget? suffix,
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
          errorText: errorText,
        ),
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
      ('8+ characters', p.length >= 8),
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
                      Text('(photo of the document)',
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

                          // ---- Password ----
                          _buildField(
                            label: AppLocalizations.of(context)!.password,
                            controller: _passwordController,
                            hint: 'At least 8 characters',
                            icon: Icons.lock_outline,
                            obscure: _obscurePassword,
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
                          // LOCATION — farmers are restricted to Laurel
                          // (BarangayLocationField, for verification);
                          // buyers can be anywhere in the Philippines
                          // (MyLocationField, a free map pin).
                          // The certificate stays farmer-only below.
                          // ================================================
                          const Divider(height: 8),
                          const SizedBox(height: 14),
                          if (_isFarmer) ...[
                            _laurelNotice(),
                            const SizedBox(height: 14),
                            BarangayLocationField(
                              value: _selectedBarangay,
                              errorText: _triedSubmit && _selectedBarangay == null
                                  ? 'Please select a barangay in Laurel.'
                                  : null,
                              onChanged: (value) => setState(() => _selectedBarangay = value),
                              onLocationDetected: (lat, lng) {
                                _pickedLat = lat;
                                _pickedLng = lng;
                              },
                            ),
                            _buildCertificatePicker(),
                          ] else
                            MyLocationField(
                              latitude: _pickedLat,
                              longitude: _pickedLng,
                              errorText: _triedSubmit && (_pickedLat == null || _pickedLng == null)
                                  ? 'Please set your location.'
                                  : null,
                              onPicked: (latLng) => setState(() {
                                _pickedLat = latLng.latitude;
                                _pickedLng = latLng.longitude;
                              }),
                            ),
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
