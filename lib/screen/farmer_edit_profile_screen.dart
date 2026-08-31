import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../services/cloudinary_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _fieldBorder = Color(0xFFDCEDC8);

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  XFile? _pickedPhoto;
  String? _photoUrl;

  bool _loading = false;
  bool _initialLoading = true;

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
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        _phoneController.text = data['phone']?.toString() ?? '';
        _photoUrl = data['photoUrl']?.toString();
        // Combine barangay/municipality/province into one display string,
        // matching how ProfileTab shows location. Adjust field names here
        // if your schema differs.
        final barangay = data['barangay']?.toString();
        final muni = data['municipality']?.toString() ?? '';
        final prov = data['province']?.toString() ?? '';
        _locationController.text = (barangay != null && barangay.isNotEmpty)
            ? '$barangay, $muni, $prov'
            : [muni, prov].where((s) => s.isNotEmpty).join(', ');
      }
    }

    if (!mounted) return;
    setState(() => _initialLoading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final location = _locationController.text.trim();

    if (name.isEmpty) {
      _showMessage('Please enter your full name.');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = _user;
      if (user != null) {
        final updateData = {
          'name': name,
          'phone': phone,
          'location': location, // simple combined string; split into
          // barangay/municipality/province fields instead if your
          // schema needs them separately.
        };

        if (_pickedPhoto != null) {
          final uploadedUrl = await _cloudinaryService.uploadImage(_pickedPhoto!);
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

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(updateData, SetOptions(merge: true));
      }
      if (!mounted) return;
      _showMessage('Profile updated!');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(message, style: GoogleFonts.montserrat(color: Colors.white)),
      ),
    );
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Choose Photo', style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                  ),
                ),
                const SizedBox(height: 4),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined, color: _dark),
                  title: Text('Take Photo', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 14)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: _dark),
                  title: Text('Choose from Gallery', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 14)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickProfilePhoto() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    final picked = await _imagePicker.pickImage(source: source, maxWidth: 1000, imageQuality: 70);
    if (picked == null || !mounted) return;

    setState(() => _pickedPhoto = picked);
  }

  void showComingSoon(String feature) => _showMessage('$feature — coming soon.');

  InputDecoration _fieldDecoration(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: _dark, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBorder, width: 1.2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _fieldBorder, width: 1.2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _dark, width: 1.6)),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(text,
          style: GoogleFonts.montserrat(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey[600], letterSpacing: 0.5)),
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
                child: imageProvider == null ? const Icon(Icons.person, color: _dark, size: 52) : null,
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
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Text('Change Photo',
              style: GoogleFonts.montserrat(fontSize: 12.5, fontWeight: FontWeight.w600, color: _dark)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: Text('Edit Profile',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87)),
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator(color: _dark))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                    enabled: false, // email changes need re-auth; edit elsewhere if needed
                    style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black54),
                    decoration: _fieldDecoration(Icons.mail_outline),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('PHONE NUMBER'),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.call_outlined),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel('LOCATION'),
                  TextField(
                    controller: _locationController,
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _fieldDecoration(Icons.location_on_outlined),
                  ),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dark,
                      disabledBackgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Save Changes', style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}