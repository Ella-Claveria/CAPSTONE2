import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../services/device_role_service.dart';
import '../services/location_permission_prompt.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/barangay_location_field.dart';
import '../widgets/my_location_field.dart';
import '../widgets/permission_rationale_dialog.dart';
import 'auth_route_handler.dart';
import 'privacy_policy_screen.dart';
import 'supported_products_screen.dart';
import 'terms_and_conditions_screen.dart';

/// Shown right after a brand-new "Continue with Google" sign-in — the
/// Google account is already authenticated with Firebase at this point
/// (see AuthService.signInWithGoogle), but there's no users/{uid} document
/// yet, so this collects the one thing Google can't tell us: which role
/// they're signing up as (and, for farmers, the same barangay +
/// certificate RegisterScreen collects for a password account).
class GoogleCompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String? initialName;
  // Pre-selects the toggle when they tapped Google sign-in on a
  // role-specific door; still changeable, same as RegisterScreen's toggle.
  final String initialRole;

  const GoogleCompleteProfileScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.initialRole,
    this.initialName,
  });

  @override
  State<GoogleCompleteProfileScreen> createState() => _GoogleCompleteProfileScreenState();
}

class _GoogleCompleteProfileScreenState extends State<GoogleCompleteProfileScreen> {
  late final _fullNameController = TextEditingController(text: widget.initialName ?? '');
  late String _selectedRole = widget.initialRole == 'farmer' ? 'farmer' : 'buyer';

  String? _selectedBarangay;
  // Only set when BarangayLocationField's "Use my location" got a real GPS
  // fix — a manually-picked barangay leaves these null.
  double? _pickedLat;
  double? _pickedLng;
  XFile? _certFile;
  Uint8List? _certBytes;
  bool _photoPromptShown = false;

  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  final _deviceRoleService = DeviceRoleService();
  final _imagePicker = ImagePicker();

  bool _loading = false;
  bool _triedSubmit = false;

  bool _agreedToTerms = false;
  bool _supportedProductsAcknowledged = false;

  bool get _isFarmer => _selectedRole == 'farmer';

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    if (_fullNameController.text.trim().length < 3) return false;
    if (_isFarmer) {
      if (_selectedBarangay == null) return false;
      if (_certFile == null) return false;
      if (!_supportedProductsAcknowledged) return false;
    } else {
      if (_pickedLat == null || _pickedLng == null) return false;
    }
    if (!_agreedToTerms) return false;
    return true;
  }

  void _selectRole(String role) {
    if (role == _selectedRole) return;
    setState(() {
      _selectedRole = role;
      // Farmer's barangay and buyer's map pin are separate fields — only
      // the certificate is farmer-only.
      if (role != 'farmer') {
        _certFile = null;
        _certBytes = null;
      }
    });
  }

  Future<void> _pickCertificate() async {
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    await _authService.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    setState(() => _triedSubmit = true);
    if (!_isFormValid) return;

    setState(() => _loading = true);

    // This device can only ever hold one role — checked here too, since
    // Google sign-up comes through this screen instead of RegisterScreen.
    final registeredRole = await _deviceRoleService.getRegisteredRole();
    if (!mounted) return;
    if (registeredRole != null && registeredRole != _selectedRole) {
      setState(() => _loading = false);
      _showMessage('This device already has a $registeredRole account. '
          'Only one role is allowed per device.');
      return;
    }

    final profileError = await _authService.completeGoogleProfile(
      uid: widget.uid,
      fullName: _fullNameController.text.trim(),
      email: widget.email,
      role: _selectedRole,
      supportedProductsAcknowledged: _isFarmer && _supportedProductsAcknowledged,
    );
    if (!mounted) return;
    if (profileError != null) {
      setState(() => _loading = false);
      _showMessage(profileError);
      return;
    }

    await _deviceRoleService.claimDevice(role: _selectedRole, uid: widget.uid);

    if (_isFarmer) {
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
        uid: widget.uid,
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
    } else {
      await _authService.saveBuyerLocation(
        uid: widget.uid,
        latitude: _pickedLat!,
        longitude: _pickedLng!,
      );
      // Also primes the separate, ongoing "sort nearby farms by distance"
      // permission used later in the marketplace — a no-op prompt-wise if
      // MyLocationField's "Use my location" already granted it above.
      if (mounted) {
        await requestBuyerLocationPermission(context);
      }
    }

    if (!mounted) return;
    final result = await AuthRoutingService.decide(widget.uid);
    if (!mounted) return;
    setState(() => _loading = false);
    await applyAuthRouteResult(context, result);
  }

  // ==========================================================
  // Farmer supported-product awareness — see register_screen.dart's
  // identical section for the full rationale; kept in sync wording-wise
  // since both screens are "Farmer setup," just reached via different
  // sign-up methods (password vs Google).
  // ==========================================================
  Widget _supportedProductsSection() {
    final showError = _triedSubmit && !_supportedProductsAcknowledged;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: showError ? Colors.red : AppTheme.mid, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_outlined, color: AppTheme.dark, size: 18),
              const SizedBox(width: 6),
              Text('Supported Products in AgriTrade+',
                  style: AppTheme.body(color: AppTheme.dark, size: 13.5).copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'AgriTrade+ currently supports selected agricultural commodities based on '
            'the products identified with the agricultural office. Only supported '
            'products can be posted in the marketplace.',
            style: AppTheme.body(color: Colors.black87, size: 12.5).copyWith(height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Please review the supported products before continuing.',
            style: AppTheme.body(color: Colors.black87, size: 12.5).copyWith(fontWeight: FontWeight.w600),
          ),
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
              child: const Text('View Supported Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _supportedProductsAcknowledged = !_supportedProductsAcknowledged),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _supportedProductsAcknowledged,
                  onChanged: (v) => setState(() => _supportedProductsAcknowledged = v ?? false),
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
                      style: AppTheme.body(color: Colors.black87, size: 12).copyWith(height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showError)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('Please confirm you understand the supported products scope.',
                  style: TextStyle(color: Colors.red, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Widget _publicLocationPreview() {
    if (_selectedBarangay == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 14),
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

  Widget _consentCheckbox() {
    final showError = _triedSubmit && !_agreedToTerms;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
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

  @override
  Widget build(BuildContext context) {
    final canSubmit = _isFormValid && !_loading;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(child: AgriTradeText(fontSize: 26)),
                      const SizedBox(height: 6),
                     Center(
                        child: Text('One last step', style: AppTheme.heading(20)),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Signed in as ${widget.email}',
                          style: AppTheme.body(color: Colors.black54, size: 12.5),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text('Full Name', style: AppTheme.label()),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _fullNameController,
                        decoration: AppTheme.inputBox(
                          hint: 'Juan F. Santos',
                          icon: Icons.person_outline,
                          errorText: _triedSubmit && _fullNameController.text.trim().length < 3
                              ? 'That name looks too short.'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text('I am a...', style: AppTheme.label()),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.fieldFill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _roleToggleOption('buyer', 'Buyer', Icons.shopping_cart_outlined)),
                            Expanded(child: _roleToggleOption('farmer', 'Farmer', Icons.agriculture_outlined)),
                          ],
                        ),
                      ),

                      if (_isFarmer) ...[
                        const SizedBox(height: 14),
                        Container(
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
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (_isFarmer) _supportedProductsSection(),
                      if (_isFarmer)
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
                        )
                      else
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
                      if (_isFarmer) _publicLocationPreview(),
                      if (_isFarmer) ...[
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
                                color: _triedSubmit && _certFile == null ? Colors.red : AppTheme.mid,
                                width: 1.2,
                              ),
                            ),
                            child: _certBytes == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.upload_file, size: 38, color: AppTheme.mid),
                                      const SizedBox(height: 8),
                                      Text('Attach your certificate', style: AppTheme.body(size: 13)),
                                      const SizedBox(height: 2),
                                      Text('(photo of the document)', style: AppTheme.body(color: Colors.black45, size: 11.5)),
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
                                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                            onPressed: _loading ? null : _removeCertificate,
                                            tooltip: 'Remove',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (_triedSubmit && _certFile == null) ...[
                          const SizedBox(height: 6),
                          const Text('Agricultural certification is required.',
                              style: TextStyle(color: Colors.red, fontSize: 11.5)),
                        ],
                      ],
                      _consentCheckbox(),
                    ],
                  ),
                ),
              ),
            ),
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
                      onPressed: canSubmit ? _finish : (_loading ? null : _finish),
                      style: AppTheme.primaryButton(),
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Finish Sign Up', style: AppTheme.buttonText()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading ? null : _cancel,
                    child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              style: AppTheme.body(color: selected ? Colors.white : Colors.black87, size: 14).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
