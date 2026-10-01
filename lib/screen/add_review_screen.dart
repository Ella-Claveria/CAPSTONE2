import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../services/cloudinary_service.dart';
import '../services/review_service.dart';

class AddReviewScreen extends StatefulWidget {
  final String orderId;
  final String productId;
  final String productName;
  final String sellerId;
  final String? productImage;

  const AddReviewScreen({
    super.key,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.sellerId,
    this.productImage,
  });

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  final _reviewService = ReviewService();
  final _cloudinary = CloudinaryService();
  final _picker = ImagePicker();
  final _commentController = TextEditingController();

  double _rating = 0;
  bool _submitting = false;
  XFile? _selectedImage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );

    if (!mounted || picked == null) return;
    setState(() => _selectedImage = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a star rating.')),
      );
      return;
    }
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a review description.')),
      );
      return;
    }

    setState(() => _submitting = true);

    String? imageUrl;
    if (_selectedImage != null) {
      imageUrl = await _cloudinary.uploadImage(
        _selectedImage!,
        folder: 'agritrade/reviews',
      );
      if (_selectedImage != null && imageUrl == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not upload review image.')),
        );
        return;
      }
    }

    final err = await _reviewService.submitReview(
      orderId: widget.orderId,
      productId: widget.productId,
      productName: widget.productName,
      sellerId: widget.sellerId,
      rating: _rating,
      comment: comment,
      imageUrl: imageUrl,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review submitted. Thank you!')),
    );
    Navigator.pop(context, true);
  }

  Widget _star(int index) {
    final fill = (_rating - (index - 1)).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final half = details.localPosition.dx < 18;
        setState(() => _rating = index - (half ? 0.5 : 0));
      },
      child: SizedBox(
        width: 36,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.star_border_rounded, color: Colors.grey, size: 32),
            if (fill > 0)
              ClipRect(
                clipper: _StarFillClipper(fill),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Review'),
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: (widget.productImage ?? '').isNotEmpty
                          ? Image.network(
                              widget.productImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: _accent,
                                child: const Icon(
                                  Icons.shopping_basket,
                                  color: _dark,
                                ),
                              ),
                            )
                          : Container(
                              color: _accent,
                              child: const Icon(
                                Icons.shopping_basket,
                                color: _dark,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your Rating (required)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => _star(i + 1)),
            ),
            Center(
              child: Text(
                _rating == 0
                    ? 'Choose 0.5 to 5 stars'
                    : '${_rating.toStringAsFixed(1)} out of 5',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Share your experience with this product...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _selectedImage == null
                    ? 'Add Image (Optional)'
                    : 'Change Image',
              ),
            ),
            if (_selectedImage != null) ...[
              const SizedBox(height: 8),
              FutureBuilder<List<int>>(
                future: _selectedImage!.readAsBytes(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Container(
                      height: 120,
                      color: _accent,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(color: _dark),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      Uint8List.fromList(snap.data!),
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(_submitting ? 'Submitting...' : 'Submit Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarFillClipper extends CustomClipper<Rect> {
  final double fill;
  const _StarFillClipper(this.fill);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fill, size.height);

  @override
  bool shouldReclip(covariant _StarFillClipper oldClipper) =>
      oldClipper.fill != fill;
}
