import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- ADDED THIS IMPORT
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import 'email_verification_screen.dart';
import '../services/connectivity_service.dart';

// ============================================================
// The 21 barangays of Laurel, Batangas.
// This is the list the barangay dropdown uses.
// ============================================================

const List<String> kLaurelBarangays = [
  'As-Is', 'Balakilong', 'Barangay 1', 'Barangay 2', 'Barangay 3',
  'Barangay 4', 'Barangay 5', 'Berinayan', 'Bugaan East', 'Bugaan West',
  'Buso-buso', 'Dayap Itaas', 'Gulod', 'J. Leviste', 'Molinete',
  'Niyugan', 'Paliparan', 'San Gabriel', 'San Gregorio', 'Santa Maria', 'Ticub',
];

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});

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

  // Farmer-only: chosen barangay + the certificate photo.
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

  // ---------- Entrance animation, matching the splash ----------
  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  final _emailPattern = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');

  bool get _isFarmer => widget.role == 'farmer';

  @override
  void initState() {
    super.initState();

    // Rebuild on every keystroke so errors + the button update live.
    _fullNameController.addListener(_onChange);
    _emailController.addListener(_onChange);
    _passwordController.addListener(_onChange);
    _confirmController.addListener(_onChange);

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

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ==========================================================
  // LIVE VALIDATION
  // ==========================================================
  bool _passwordMeetsRules(String p) =>
      p.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(p) &&
      RegExp(r'[0-9]').hasMatch(p);

  String? get _nameError {
    final name = _fullNameController.text.trim();
    if (name.isEmpty) return null;
    if (name.length < 3) return 'Masyadong maikli ang pangalan.';
    return null;
  }

  String? get _emailError {
    final email = _emailController.text.trim();
    if (email.isEmpty) return null;
    if (!_emailPattern.hasMatch(email)) return 'Mukhang mali ang format ng email.';
    return null;
  }

  String? get _passwordError {
    final p = _passwordController.text;
    if (p.isEmpty) return null;
    if (p.length < 8) return 'Dapat hindi bababa sa 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'[0-9]').hasMatch(p)) {
      return 'Dapat may letra at numero.';
    }
    return null;
  }

  String? get _confirmError {
    final c = _confirmController.text;
    if (c.isEmpty) return null;
    if (c != _passwordController.text) return 'Hindi magkatugma ang password.';
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
      _showMessage('Walang internet connection. Pakisuri ang iyong koneksyon.');
      return;
    }

    setState(() => _loading = true);

    // ---- Step 1: create the account ----
    final error = await _authService.signUp(
      fullName: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: widget.role,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() => _loading = false);
      _showMessage(error);
      return;
    }

    // ---- Step 2: farmers only — upload the certificate ----
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
          _showMessage('Hindi na-upload ang certificate. Subukan ulit.');
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

        // ==========================================================
        // NEW CODE ADDED HERE: Add missing fields for the Admin Dashboard
        // ==========================================================
        try {
          await FirebaseFirestore.instance.collection('verificationDocs').doc(uid).set({
            'status': 'pending',
            'fullName': _fullNameController.text.trim(),
            'userId': uid,
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Error attaching admin fields: $e');
        }
        // ==========================================================
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // ---- Step 3: go verify the email ----
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          role: widget.role,
          email: _emailController.text.trim(),
        ),
      ),
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
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          decoration: AppTheme.inputBox(
            hint: hint,
            icon: icon,
            suffix: suffix,
            errorText: errorText,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ==========================================================
  // Barangay dropdown (Laurel only)
  // ==========================================================
  Widget _buildBarangayDropdown() {
    final showError = _triedSubmit && _selectedBarangay == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Barangay (Laurel)', style: AppTheme.label()),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedBarangay,
          isExpanded: true,
          decoration: AppTheme.inputBox(
            hint: 'Piliin ang iyong barangay',
            icon: Icons.location_on_outlined,
            errorText: showError ? 'Pumili ng barangay sa Laurel.' : null,
          ),
          items: kLaurelBarangays
              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
              .toList(),
          onChanged: (value) => setState(() => _selectedBarangay = value),
        ),
        const SizedBox(height: 16),
      ],
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
                      Text('I-attach ang iyong certificate',
                          style: AppTheme.body(size: 13)),
                      const SizedBox(height: 2),
                      Text('(larawan ng dokumento)',
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
                            tooltip: 'Alisin',
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Text('Kailangan ang agricultural certification.',
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
      body: Container(
        decoration: const BoxDecoration(
          color: AppTheme.dark,
          image: DecorationImage(
            image: AssetImage('assets/background_login.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.authCard(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ---- Back button ----
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.arrow_back,
                                color: AppTheme.dark),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // ---- Logo ----
                        Center(
                          child: Image.asset(
                            'assets/logo.png',
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
                          child: Text('Create an Account',
                              style: AppTheme.heading(20)),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            _isFarmer ? 'as a Farmer' : 'as a Buyer',
                            style: AppTheme.body(
                                color: Colors.black54, size: 13.5),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ---- Full name ----
                        _buildField(
                          label: 'Full Name',
                          controller: _fullNameController,
                          hint: 'Juan F. Santos',
                          icon: Icons.person_outline,
                          errorText: _nameError,
                        ),

                        // ---- Email ----
                        _buildField(
                          label: 'Email Address',
                          controller: _emailController,
                          hint: 'juansantos@gmail.com',
                          icon: Icons.email_outlined,
                          keyboard: TextInputType.emailAddress,
                          errorText: _emailError,
                        ),

                        // ---- Password ----
                        _buildField(
                          label: 'Password',
                          controller: _passwordController,
                          hint: 'At least 8 characters',
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

                        // ---- Confirm password ----
                        _buildField(
                          label: 'Confirm Password',
                          controller: _confirmController,
                          hint: 'Ulitin ang password',
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
                        // FARMER VERIFICATION — farmers only.
                        // Buyers never see this section.
                        // ================================================
                        if (_isFarmer) ...[
                          const Divider(height: 8),
                          const SizedBox(height: 14),
                          _buildBarangayDropdown(),
                          _buildCertificatePicker(),
                        ],

                        const SizedBox(height: 6),

                        // ---- Sign up button ----
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canSubmit ? _register : null,
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
                                : Text('Sign Up',
                                    style: AppTheme.buttonText()),
                          ),
                        ),

                        // Gentle hint when the button is disabled.
                        if (!_isFormValid && !_loading) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Kumpletuhin muna ang lahat ng field.',
                              style: AppTheme.body(
                                  color: Colors.black45, size: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // ---- Back to login ----
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: RichText(
                              text: TextSpan(
                                style: AppTheme.body(
                                    color: Colors.black87, size: 13.5),
                                children: [
                                  const TextSpan(
                                      text: 'Already have an account? '),
                                  TextSpan(
                                    text: 'Sign in',
                                    style: AppTheme.body(
                                      color: AppTheme.dark,
                                      size: 13.5,
                                    ).copyWith(fontWeight: FontWeight.bold),
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
          ),
        ),
      ),
    );
  }
}