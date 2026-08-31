// ============================================================
// farmer_verification_field.dart
// ------------------------------------------------------------
// Put this at: lib/widgets/farmer_verification_field.dart
//
// WHAT IT'S FOR:
// Your paper says only VERIFIED local farmers from Laurel may
// sell (FR-028). But an admin can't approve anyone without
// evidence. This widget collects that evidence during signup.
//
// It gathers two things:
//   1. The barangay in Laurel (proves locality)
//   2. A photo of their agricultural certification
//
// HOW TO USE IT — inside your register_screen.dart, show it
// only for farmers:
//
//     if (widget.role == 'farmer')
//       FarmerVerificationField(
//         barangayController: _barangayController,
//         onDocumentChanged: (base64) {
//           _certificationBase64 = base64;
//         },
//       ),
//
// Then when you save the account, pass _certificationBase64
// to your AuthService (see farmer_verification_service.dart).
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

class FarmerVerificationField extends StatefulWidget {
  /// Holds the barangay text the farmer types.
  final TextEditingController barangayController;

  /// Called whenever the document changes. Gives you the photo
  /// as Base64 text, or null if they removed it.
  final ValueChanged<String?> onDocumentChanged;

  /// Optional error text shown under the upload box.
  final String? documentError;

  const FarmerVerificationField({
    super.key,
    required this.barangayController,
    required this.onDocumentChanged,
    this.documentError,
  });

  @override
  State<FarmerVerificationField> createState() =>
      _FarmerVerificationFieldState();
}

class _FarmerVerificationFieldState extends State<FarmerVerificationField> {
  // Certificates need to stay readable, so we allow a bit more
  // detail than product photos — but still small enough to fit
  // safely inside one Firestore document.
  static const double _maxSide = 1200;
  static const int _quality = 80;
  static const int _maxBytes = 800000; // ~800 KB

  final ImagePicker _picker = ImagePicker();

  String? _base64;
  String? _fileName;
  int _sizeKb = 0;
  bool _busy = false;

  // ----------------------------------------------------------
  // Let the farmer choose: camera or gallery.
  // Most will just photograph the paper certificate.
  // ----------------------------------------------------------
  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.dark),
              title: const Text('Kunan ng litrato'),
              subtitle: const Text('Gamitin ang camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: AppTheme.dark),
              title: const Text('Pumili sa gallery'),
              subtitle: const Text('Mga naka-save na larawan'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source != null) _pickDocument(source);
  }

  Future<void> _pickDocument(ImageSource source) async {
    setState(() => _busy = true);

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        imageQuality: _quality,
      );

      if (file == null) {
        setState(() => _busy = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final encoded = base64Encode(bytes);

      // Guard against oversized documents before they ever reach
      // Firestore, so the farmer gets a clear message instead of
      // a confusing save failure later.
      if (encoded.length > _maxBytes) {
        setState(() => _busy = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Masyadong malaki ang file '
              '(${(encoded.length / 1024).round()} KB). '
              'Subukan ulit na mas malapit ang kuha.',
            ),
          ),
        );
        return;
      }

      setState(() {
        _base64 = encoded;
        _fileName = file.name;
        _sizeKb = (encoded.length / 1024).round();
        _busy = false;
      });

      widget.onDocumentChanged(encoded);
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hindi nakuha ang file. Subukan ulit.')),
      );
    }
  }

  void _removeDocument() {
    setState(() {
      _base64 = null;
      _fileName = null;
      _sizeKb = 0;
    });
    widget.onDocumentChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Section heading ----
        Row(
          children: [
            const Icon(Icons.verified_user_outlined,
                size: 18, color: AppTheme.dark),
            const SizedBox(width: 6),
            Text('Farmer Verification', style: AppTheme.label()),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Para masiguro na tunay na magsasaka mula sa Laurel, '
          'Batangas ang nagbebenta.',
          style: AppTheme.body(size: 12),
        ),
        const SizedBox(height: 14),

        // ---- Barangay ----
        Text('Barangay sa Laurel', style: AppTheme.label()),
        const SizedBox(height: 8),
        TextField(
          controller: widget.barangayController,
          decoration: AppTheme.inputBox(
            hint: 'hal. Brgy. Balakilong',
            icon: Icons.place_outlined,
          ),
        ),
        const SizedBox(height: 16),

        // ---- Certification upload ----
        Text('Agricultural Certification', style: AppTheme.label()),
        const SizedBox(height: 8),

        if (_base64 == null)
          _uploadBox()
        else
          _filePreview(),

        // Error text, if the parent screen passed one.
        if (widget.documentError != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.documentError!,
            style: const TextStyle(
                color: Colors.redAccent, fontSize: 11.5),
          ),
        ],

        const SizedBox(height: 14),

        // ---- Compliance notice ----
        _complianceNotice(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ----------------------------------------------------------
  // The empty "Choose File" state.
  // ----------------------------------------------------------
  Widget _uploadBox() {
    return InkWell(
      onTap: _busy ? null : _chooseSource,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.accent,
            width: 1.4,
          ),
        ),
        child: Column(
          children: [
            if (_busy)
              const SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppTheme.mid,
                ),
              )
            else
              const Icon(Icons.upload_file_outlined,
                  size: 30, color: AppTheme.mid),
            const SizedBox(height: 10),
            Text(
              _busy ? 'Ineeproseso...' : 'Choose File',
              style: AppTheme.label().copyWith(color: AppTheme.dark),
            ),
            const SizedBox(height: 4),
            Text(
              'Litrato ng iyong sertipikasyon',
              style: AppTheme.body(size: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // Shown once a file is attached.
  // ----------------------------------------------------------
  Widget _filePreview() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent, width: 1.2),
      ),
      child: Row(
        children: [
          // Thumbnail of what they attached.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(_base64!),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 15, color: AppTheme.mid),
                    const SizedBox(width: 4),
                    Text('Naka-attach',
                        style: AppTheme.label().copyWith(
                            fontSize: 13, color: AppTheme.dark)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _fileName ?? 'certification',
                  style: AppTheme.body(size: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
                Text('$_sizeKb KB', style: AppTheme.body(size: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
            tooltip: 'Alisin',
            onPressed: _removeDocument,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // The compliance box from your mockup.
  // ----------------------------------------------------------
  Widget _complianceNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: AppTheme.dark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compliance Protocol',
                  style: AppTheme.label()
                      .copyWith(fontSize: 12.5, color: AppTheme.dark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Upang mapanatili ang integridad ng marketplace, '
                  'sinusuri ang lahat ng rehistrasyon ng isang '
                  'opisyal ng Department of Agriculture. Karaniwang '
                  'tumatagal ng 24 hanggang 48 oras.',
                  style: AppTheme.body(size: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}