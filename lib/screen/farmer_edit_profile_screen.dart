import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import '../widgets/recovery_email_code_dialog.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../services/geocoding_service.dart';
import '../services/ph_mobile.dart';
import '../widgets/buyer_location_picker.dart';
import 'set_farm_location_screen.dart';
import '../l10n/tr.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _fieldBorder = Color(0xFFDCEDC8);

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _recoveryEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  XFile? _pickedPhoto;
  String? _photoUrl;
  String? _role;
  double? _latitude;
  double? _longitude;
  // A buyer's saved region/province/city/barangay, for reopening the
  // location popup where they left off.
  BuyerLocationResult? _buyerLocation;

  bool _loading = false;
  bool _savingLocation = false;
  bool _initialLoading = true;
  bool _recoveryEmailVerified = false;
  // The recovery email as saved on the account (what Verified is about).
  String _savedRecoveryEmail = '';
  bool _verifyingRecovery = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _user;
    _nameController.text = user?.displayName ?? '';
    _emailController.text = user?.email ?? '';

    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      // Exact coordinates live under users/{uid}/private/geo, not on the
      // main doc just read above — only this account (the owner) or an
      // admin can read it (see firestore.rules).
      final geoDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('geo')
          .get();
      final geo = geoDoc.data();
      _latitude = (geo?['latitude'] as num?)?.toDouble();
      _longitude = (geo?['longitude'] as num?)?.toDouble();
      if (data != null) {
        // Registration saves 'mobileNumber'; this screen used to save
        // 'phone'. Either is read, in whatever format it was stored, and
        // shown as the 10 digits after +63.
        _phoneController.text = phMobileLocalDigits(
          (data['mobileNumber'] ?? data['phone'])?.toString(),
        );
        // A recovery email is a second address: empty until the user adds
        // one (never pre-filled with the login email), and Verified only
        // once its code has been entered.
        final storedRecovery = (data['recoveryEmail'] ?? '').toString().trim();
        _recoveryEmailController.text = _sameAsLogin(storedRecovery)
            ? ''
            : storedRecovery;
        _savedRecoveryEmail = _recoveryEmailController.text;
        _recoveryEmailVerified =
            _savedRecoveryEmail.isNotEmpty &&
            data['recoveryEmailVerified'] == true;
        _recoveryEmailController.addListener(() => setState(() {}));
        _photoUrl = data['photoUrl']?.toString();
        _role = data['role']?.toString();
        // Combine barangay/municipality/province into one display string,
        // matching how ProfileTab shows location. Adjust field names here
        // if your schema differs.
        final barangay = data['barangay']?.toString();
        final muni = data['municipality']?.toString() ?? '';
        final prov = data['province']?.toString() ?? '';
        _locationController.text = (barangay != null && barangay.isNotEmpty)
            ? '$barangay, $muni, $prov'
            : [muni, prov].where((s) => s.isNotEmpty).join(', ');
        final region = data['region']?.toString() ?? '';
        if (barangay != null &&
            barangay.isNotEmpty &&
            muni.isNotEmpty &&
            prov.isNotEmpty) {
          _buyerLocation = BuyerLocationResult(
            region: region.isNotEmpty ? region : prov,
            province: prov,
            city: muni,
            barangay: barangay,
          );
        }
      }
    }

    if (!mounted) return;
    setState(() => _initialLoading = false);
    _lookUpPinPlace();
  }

  // The place the farm pin is actually in (barangay, town, province),
  // looked up from its coordinates. Until it is known — or if the lookup
  // fails — the registered location stands in.
  String? _pinPlace;

  Future<void> _lookUpPinPlace() async {
    final lat = _latitude, lng = _longitude;
    // Only farmers have the Farm Location box.
    if (lat == null || lng == null || _role != 'farmer') return;
    final address = await GeocodingService.reverseGeocode(lat, lng);
    if (!mounted || lat != _latitude || lng != _longitude) return;
    final place = address?.readable.trim() ?? '';
    setState(() => _pinPlace = place.isEmpty ? null : place);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _recoveryEmailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phoneDigits = _phoneController.text.trim();
    // Always stored as +639XXXXXXXXX.
    final phone = phMobileE164(phoneDigits);
    final location = _locationController.text.trim();
    final recoveryEmail = _recoveryEmailController.text.trim();

    // Required, like at registration — it is what Place Order starts from.
    if (phoneDigits.isEmpty) {
      _showMessage('Mobile number is required.');
      return;
    }
    if (!isValidPhMobile(phoneDigits)) {
      _showMessage(kPhMobileInvalidMessage);
      return;
    }
    if (name.isEmpty) {
      _showMessage('Please enter your full name.');
      return;
    }
    if (recoveryEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(recoveryEmail)) {
      _showMessage('Please enter a valid recovery email.');
      return;
    }
    if (_sameAsLogin(recoveryEmail)) {
      _showMessage(_sameAsLoginMessage);
      return;
    }

    setState(() => _loading = true);
    try {
      final user = _user;
      if (user != null) {
        final Map<String, dynamic> updateData = {
          'name': name,
          'fullName': name,
          // Both names, so every reader sees the same number: 'mobileNumber'
          // (Registration, Place Order) and 'phone' (the admin views).
          'phone': phone,
          'mobileNumber': phone,
          'location': location, // simple combined string; split into
          // barangay/municipality/province fields instead if your
          // schema needs them separately.
          // An emptied recovery email field removes the saved one.
          if (_recoveryRemoved) ...{
            'recoveryEmail': FieldValue.delete(),
            'recoveryEmailVerified': FieldValue.delete(),
            'recoveryEmailVerifiedAt': FieldValue.delete(),
          },
        };

        if (_pickedPhoto != null) {
          final uploadedUrl = await _cloudinaryService.uploadImage(
            _pickedPhoto!,
          );
          if (uploadedUrl == null || uploadedUrl.isEmpty) {
            throw Exception('Could not upload profile photo.');
          }
          updateData['photoUrl'] = uploadedUrl;
          _photoUrl = uploadedUrl;
          await user.updatePhotoURL(uploadedUrl);
        }

        if (user.displayName != name) {
          await user.updateDisplayName(name);
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(updateData, SetOptions(merge: true));
      }
      if (!mounted) return;
      // A new recovery email is saved — and verified — by entering the code
      // emailed to it (never by changing the sign-in email).
      if (_recoveryChanged) {
        setState(() => _loading = false);
        await _verifyRecovery();
        if (!mounted) return;
      } else {
        if (_recoveryRemoved) {
          _savedRecoveryEmail = '';
          _recoveryEmailVerified = false;
        }
        _showMessage('Profile updated!');
      }
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // A saved recovery email whose field was emptied.
  bool get _recoveryRemoved =>
      _savedRecoveryEmail.isNotEmpty &&
      _recoveryEmailController.text.trim().isEmpty;

  bool get _recoveryChanged {
    final typed = _recoveryEmailController.text.trim();
    return typed.isNotEmpty &&
        typed.toLowerCase() != _savedRecoveryEmail.toLowerCase();
  }

  // A recovery email of its own is in the field (not empty, not the
  // login email) — only then is there a status to show.
  bool get _hasOwnRecoveryEmail {
    final typed = _recoveryEmailController.text.trim();
    return typed.isNotEmpty && !_sameAsLogin(typed);
  }

  static const String _sameAsLoginMessage =
      'Use a different email from the one you log in with.';

  // The login email cannot be its own recovery email.
  bool _sameAsLogin(String email) {
    final login = (_user?.email ?? '').trim().toLowerCase();
    return email.isNotEmpty && email.trim().toLowerCase() == login;
  }

  // Emails a code to the recovery email in the field and asks for it.
  Future<void> _verifyRecovery() async {
    final email = _recoveryEmailController.text.trim();
    if (email.isEmpty || _verifyingRecovery) return;
    setState(() => _verifyingRecovery = true);
    final verified = await verifyRecoveryEmail(context, email);
    if (!mounted) return;
    setState(() {
      _verifyingRecovery = false;
      // Requesting the code saved the address, verified or not.
      _savedRecoveryEmail = email;
      _recoveryEmailVerified = verified;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(
          message,
          style: GoogleFonts.montserrat(color: Colors.white),
        ),
      ),
    );
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showAgriSheet<ImageSource>(
      context: context,
      title: 'Choose Photo',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgriSheetAction(
            icon: Icons.photo_camera_outlined,
            label: 'Take Photo',
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          AgriSheetAction(
            icon: Icons.photo_library_outlined,
            label: 'Choose from Gallery',
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1000,
      imageQuality: 70,
    );
    if (picked == null || !mounted) return;

    setState(() => _pickedPhoto = picked);
  }

  void showComingSoon(String feature) =>
      _showMessage('$feature — coming soon.');

  // The buyer's location: the same popup as Place Order and Delivery &
  // Pickup, saved the same way — the readable area on the profile, the
  // coordinates (when there are any) only under private/geo.
  Future<void> _editBuyerLocation([BuildContext? fieldContext]) async {
    final user = _user;
    if (user == null || _savingLocation) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // The choices open right under the Location field.
    final picked = await showBuyerLocationOptions(
      context,
      initial: _buyerLocation,
      anchorContext: fieldContext,
    );
    if (picked == null || !mounted) return;

    setState(() => _savingLocation = true);
    final error = await AuthService().saveBuyerLocation(
      uid: user.uid,
      latitude: picked.latitude,
      longitude: picked.longitude,
      region: picked.region,
      province: picked.province,
      city: picked.city,
      barangay: picked.barangay,
    );
    if (!mounted) return;
    setState(() {
      _savingLocation = false;
      if (error == null) {
        _buyerLocation = picked;
        _locationController.text = picked.readable;
      }
    });
    _showMessage(error ?? 'Location updated.');
  }

  Future<void> _openLocationPicker() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => SetFarmLocationScreen(
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      _pinPlace = null;
    });
    _lookUpPinPlace();
    _showMessage('Farm location saved!');
  }

  Widget _farmLocationSection() {
    final hasLocation = _latitude != null && _longitude != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.tint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _fieldBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.location_on : Icons.location_off_outlined,
            color: _dark,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farm Location',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                // The place the pin is in (barangay, town, province), not
                // its coordinates; the registered location until known.
                Text(
                  hasLocation
                      ? (_pinPlace ??
                            (_locationController.text.trim().isNotEmpty
                                ? _locationController.text.trim()
                                : 'Set on the map'))
                      : 'Not pinned yet — buyers and admin can\'t see your farm on the map.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openLocationPicker,
            child: Text(
              hasLocation ? 'Update' : 'Set on Map',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: _dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: _dark, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: _fieldBorder, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: _fieldBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: _dark, width: 1.6),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _avatarWithEditBadge() {
    final ImageProvider? imageProvider;
    if (_pickedPhoto != null) {
      imageProvider = FileImage(File(_pickedPhoto!.path));
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_photoUrl!);
    } else {
      imageProvider = null;
    }

    return Column(
      children: [
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: _accent,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? const Icon(Icons.person, color: _dark, size: 52)
                    : null,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: GestureDetector(
                  onTap: _pickProfilePhoto,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _dark,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Text(
            'Change Photo',
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _dark,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgriAppBar(title: tr(context).editProfile),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator(color: _dark))
          : SingleChildScrollView(
              // Room between the header and the photo.
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _avatarWithEditBadge(),
                  const SizedBox(height: 24),

                  _fieldLabel('FULL NAME'),
                  TextField(
                    controller: _nameController,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.person_outline),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('EMAIL ADDRESS'),
                  TextField(
                    controller: _emailController,
                    enabled:
                        false, // email changes need re-auth; edit elsewhere if needed
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    decoration: _fieldDecoration(Icons.mail_outline),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('RECOVERY EMAIL'),
                  TextField(
                    controller: _recoveryEmailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.security_outlined)
                        .copyWith(
                          hintText: 'Add a backup email',
                          // Verified / Not verified only for a second
                          // address (not the login email): Verified once
                          // its code was entered, a newly typed one not yet.
                          suffixIcon: !_hasOwnRecoveryEmail
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: RecoveryEmailStatusChip(
                                    verified:
                                        _recoveryEmailVerified &&
                                        !_recoveryChanged,
                                  ),
                                ),
                          suffixIconConstraints: const BoxConstraints(),
                          errorText: _sameAsLogin(_recoveryEmailController.text)
                              ? _sameAsLoginMessage
                              : null,
                          helperText:
                              !_hasOwnRecoveryEmail ||
                                  (_recoveryEmailVerified && !_recoveryChanged)
                              ? null
                              : 'We will email it a 6-digit code to verify it.',
                          helperStyle: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                  ),
                  // A saved but unverified address can be verified now.
                  if (!_recoveryEmailVerified &&
                      !_recoveryChanged &&
                      _hasOwnRecoveryEmail)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _verifyingRecovery ? null : _verifyRecovery,
                        icon: _verifyingRecovery
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _dark,
                                ),
                              )
                            : const Icon(
                                Icons.mark_email_read_outlined,
                                size: 16,
                              ),
                        label: const Text('Verify now'),
                        style: TextButton.styleFrom(
                          foregroundColor: _dark,
                          textStyle: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),

                  _fieldLabel('PHONE NUMBER'),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: kPhMobileInputFormatters,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.call_outlined).copyWith(
                      // Fixed, not editable: only the 10 digits after it are.
                      prefixText: kPhMobilePrefix,
                      prefixStyle: GoogleFonts.montserrat(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.dark,
                      ),
                      hintText: kPhMobileHint,
                    ),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('LOCATION'),
                  if (_role == 'buyer')
                    Builder(
                      builder: (fieldContext) => TextField(
                        controller: _locationController,
                        readOnly: true,
                        onTap: () => _editBuyerLocation(fieldContext),
                        style: GoogleFonts.montserrat(fontSize: 14),
                        decoration: _fieldDecoration(Icons.location_on_outlined)
                            .copyWith(
                              hintText: 'Tap to set your location',
                              suffixIcon: _savingLocation
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _dark,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.grey,
                                    ),
                            ),
                      ),
                    )
                  else
                    TextField(
                      controller: _locationController,
                      style: GoogleFonts.montserrat(fontSize: 14),
                      decoration: _fieldDecoration(Icons.location_on_outlined),
                    ),

                  if (_role == 'farmer') ...[
                    const SizedBox(height: 14),
                    _farmLocationSection(),
                  ],
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dark,
                      disabledBackgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            tr(context).saveChanges,
                            style: GoogleFonts.montserrat(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
