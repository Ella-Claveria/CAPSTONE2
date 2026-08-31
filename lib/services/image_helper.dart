// ============================================================
// image_helper.dart
// ------------------------------------------------------------
// Put this at: lib/services/image_helper.dart
//
// WHAT THIS SOLVES:
// Firestore has a hard limit of 1 MB per document. A photo
// straight from a phone camera is 2–5 MB, and turning it into
// Base64 text makes it about 33% BIGGER. So an uncompressed
// photo would break your app the moment a farmer uploads one.
//
// THE FIX:
// We shrink the photo to 800x800 and drop the quality to 70%
// BEFORE converting it to text. A typical result is 40–80 KB
// — comfortably inside the limit, and still perfectly clear on
// a phone screen.
//
// The compression happens inside image_picker itself, so we
// don't need any extra package.
//
// FIRST: run this once in your terminal
//     flutter pub add image_picker
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageHelper {
  // ----------------------------------------------------------
  // TUNING KNOBS
  // ----------------------------------------------------------
  // Lower these if photos still come out too big.
  // 800px is plenty for a product photo on a phone.
  static const double _maxWidth = 800;
  static const double _maxHeight = 800;
  static const int _quality = 70; // 0-100; 70 is a good balance

  // Firestore's limit is 1,048,576 bytes for the WHOLE document.
  // We cap the image well below that so there's room for the
  // product name, price, description, and other fields.
  static const int _maxBase64Bytes = 700000; // ~700 KB

  static final ImagePicker _picker = ImagePicker();

  // ==========================================================
  // PICK FROM GALLERY
  // ----------------------------------------------------------
  // Returns the photo as a Base64 string ready to save in
  // Firestore, or null if the user cancelled.
  //
  // Throws a readable message if the photo is still too large.
  // ==========================================================
  static Future<String?> pickFromGallery() async {
    return _pick(ImageSource.gallery);
  }

  // ==========================================================
  // TAKE A NEW PHOTO WITH THE CAMERA
  // ==========================================================
  static Future<String?> pickFromCamera() async {
    return _pick(ImageSource.camera);
  }

  // ----------------------------------------------------------
  // The shared logic behind both options above.
  // ----------------------------------------------------------
  static Future<String?> _pick(ImageSource source) async {
    // These three lines do the compression for us.
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: _maxWidth,
      maxHeight: _maxHeight,
      imageQuality: _quality,
    );

    // User backed out without choosing anything.
    if (file == null) return null;

    // Read the compressed file as raw bytes.
    final bytes = await file.readAsBytes();

    // Convert those bytes into text (Base64) so it can live
    // inside a Firestore document.
    final base64String = base64Encode(bytes);

    // SAFETY CHECK: never let an oversized image through, or
    // Firestore will reject the whole save with a confusing
    // error later.
    if (base64String.length > _maxBase64Bytes) {
      throw ImageTooLargeException(
        'Masyadong malaki ang larawan '
        '(${(base64String.length / 1024).round()} KB). '
        'Pumili ng mas maliit na larawan.',
      );
    }

    return base64String;
  }

  // ==========================================================
  // Helper: how big is a stored image, in KB?
  // Useful when debugging.
  // ==========================================================
  static int sizeInKb(String? base64String) {
    if (base64String == null || base64String.isEmpty) return 0;
    return (base64String.length / 1024).round();
  }
}

// ============================================================
// A clear, catchable error for oversized images.
// ============================================================
class ImageTooLargeException implements Exception {
  final String message;
  ImageTooLargeException(this.message);

  @override
  String toString() => message;
}

// ============================================================
// Base64Image
// ------------------------------------------------------------
// Displays an image that was stored as a Base64 string.
//
// The parameter names here MATCH the ones your existing screens
// already use, so farmer_home_screen and buyer_marketplace_screen
// need no changes:
//
//     base64Data  — the stored image text (may be null)
//     fallback    — what to show when there's no image
//
// It handles three cases safely:
//   - no image at all      -> shows your fallback widget
//   - corrupted image data -> shows your fallback widget
//   - valid image          -> shows the photo
// ============================================================
class Base64Image extends StatelessWidget {
  /// The image stored as Base64 text. Null or empty is fine.
  final String? base64Data;

  /// Shown when there is no image, or the data can't be decoded.
  /// If you don't pass one, a simple grey-green box appears.
  final Widget? fallback;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  const Base64Image({
    super.key,
    required this.base64Data,
    this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    // ---- Case 1: nothing stored ----
    if (base64Data == null || base64Data!.isEmpty) {
      return fallback ?? _defaultPlaceholder(Icons.image_outlined);
    }

    // ---- Case 2: try to decode it ----
    try {
      final bytes = base64Decode(base64Data!);

      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          // Valid Base64, but not actually a usable image.
          errorBuilder: (context, error, stackTrace) =>
              fallback ?? _defaultPlaceholder(Icons.broken_image_outlined),
        ),
      );
    } catch (e) {
      // ---- Case 3: the text wasn't valid Base64 ----
      return fallback ?? _defaultPlaceholder(Icons.broken_image_outlined);
    }
  }

  Widget _defaultPlaceholder(IconData icon) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0E3),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        icon,
        color: const Color(0xFF558B2F),
        size: (width != null && width! < 60) ? 20 : 30,
      ),
    );
  }
}