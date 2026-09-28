import 'dart:typed_data';

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
    } else {
      if (_pickedLat == null || _pickedLng == null) return false;
    }
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
    final result = await AuthRoutingService.decide(widget.uid);
    if (!mounted) return;
    setState(() => _loading = false);
    await applyAuthRouteResult(context, result);
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
