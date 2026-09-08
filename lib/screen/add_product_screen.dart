import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/product_service.dart';
import '../services/cloudinary_service.dart';
import '../services/price_recommendation_service.dart';

class AddProductScreen extends StatefulWidget {
  final String? productId;
  final Map<String, dynamic>? existingData;

  const AddProductScreen({super.key, this.productId, this.existingData});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  static const Color _darkGreen = Color(0xFF1B5E20);
  static const Color _midGreen = Color(0xFF2E7D32);
  static const Color _lightGreenBg = Color(0xFFF1F8E9);
  static const Color _lightGreenAccent = Color(0xFFDCEDC8);

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _wholesaleMinimumController = TextEditingController(text: '10');
  final _retailMaximumController = TextEditingController(text: '1');
  final _quantityController = TextEditingController();
  final _descriptionController = TextEditingController();

  final ProductService _productService = ProductService();
  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  String? _category;
  final List<String> _categories = ['Fruits', 'Vegetables', 'Livestock'];

  bool _deliveryAvailable = false;
  bool _pickupOnly = false;
  bool _loading = false;
  bool _isArchived = false;

  // Single photo slot. Holds either a freshly-picked file (+ preview bytes)
  // or an existing URL (when editing).
  XFile? _file;
  Uint8List? _bytes;
  String? _imageUrl;

  bool get _isEditing => widget.productId != null;

  // ==========================================================
  // LIVE MARKET DATA — active listings, completed sales, and the
  // admin-set baseline price, kept in sync via Firestore streams
  // and fed into PriceRecommendationService. See _computeRecommendation.
  // ==========================================================
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _liveProducts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _completedOrders = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _marketPrices = [];
  StreamSubscription? _productsSub;
  StreamSubscription? _ordersSub;
  StreamSubscription? _marketPricesSub;

  void _listenToMarketData() {
    _productsSub = FirebaseFirestore.instance
        .collection('products')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _liveProducts = snap.docs);
    });
    _ordersSub = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _completedOrders = snap.docs);
    });
    _marketPricesSub = FirebaseFirestore.instance
        .collection('market_prices')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _marketPrices = snap.docs);
    });
  }

  double? _numField(Map<String, dynamic> data, String field) {
    final raw = data[field];
    if (raw is num) return raw.toDouble();
    return num.tryParse(raw?.toString() ?? '')?.toDouble();
  }

  PriceRecommendation? _computeRecommendation(String typedName) {
    final listingPrices = <double>[];
    for (final doc in _liveProducts) {
      if (widget.productId != null && doc.id == widget.productId) continue;
      final data = doc.data();
      if (!PriceRecommendationService.namesLikelyMatch(
          typedName, (data['name'] ?? '').toString())) {
        continue;
      }
      final price = _numField(data, 'price');
      if (price != null && price > 0) listingPrices.add(price);
    }

    final transactionPrices = <double>[];
    for (final doc in _completedOrders) {
      final data = doc.data();
      if (!PriceRecommendationService.namesLikelyMatch(
          typedName, (data['productName'] ?? '').toString())) {
        continue;
      }
      final price = _numField(data, 'unitPrice');
      if (price != null && price > 0) transactionPrices.add(price);
    }

    double? baselinePrice;
    for (final doc in _marketPrices) {
      final data = doc.data();
      if (!PriceRecommendationService.namesLikelyMatch(
          typedName, (data['name'] ?? '').toString())) {
        continue;
      }
      final price = _numField(data, 'baselinePrice');
      if (price != null && price > 0) {
        baselinePrice = price;
        break;
      }
    }

    return PriceRecommendationService.recommend(
      listingPrices: listingPrices,
      transactionPrices: transactionPrices,
      baselinePrice: baselinePrice,
    );
  }

  @override
  void initState() {
    super.initState();
    final data = widget.existingData;
    if (data != null) {
      _nameController.text = data['name']?.toString() ?? '';
      _priceController.text = (data['price'] as num?)?.toString() ?? '';
      _wholesalePriceController.text =
          (data['wholesalePrice'] as num?)?.toString() ?? '';
      _wholesaleMinimumController.text =
          (data['wholesaleMinimumQuantity'] as num?)?.toString() ?? '10';
      _retailMaximumController.text =
          (data['retailMaximumQuantity'] as num?)?.toString() ?? '1';
      _quantityController.text = (data['quantity'] as num?)?.toString() ?? '';
      _descriptionController.text = data['description']?.toString() ?? '';
      final category = data['category']?.toString();
      if (category != null && _categories.contains(category)) {
        _category = category;
      }
      _deliveryAvailable = data['deliveryAvailable'] == true;
      _pickupOnly = data['pickupOnly'] == true;
      _isArchived = data['isArchived'] == true;

      // Load existing image (new 'imageUrls' list, or old single 'imageUrl').
      final list =
          (data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (list.isNotEmpty) {
        _imageUrl = list.first;
      } else {
        final single = data['imageUrl']?.toString();
        if (single != null && single.isNotEmpty) _imageUrl = single;
      }
    }
    // Rebuild the price suggestion as the user types the product title.
    _nameController.addListener(() => setState(() {}));
    _listenToMarketData();
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _ordersSub?.cancel();
    _marketPricesSub?.cancel();
    _nameController.dispose();
    _priceController.dispose();
    _wholesalePriceController.dispose();
    _wholesaleMinimumController.dispose();
    _retailMaximumController.dispose();
    _quantityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _imageSourceSheet(),
    );
    if (source == null) return;

    final XFile? picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1000,
      imageQuality: 70,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _file = picked;
      _bytes = bytes;
      _imageUrl = null; // a new photo replaces any old one
    });
  }

  Widget _imageSourceSheet() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add Photo',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: _darkGreen,
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: _darkGreen,
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removeImage() {
    setState(() {
      _file = null;
      _bytes = null;
      _imageUrl = null;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final wholesalePriceText = _wholesalePriceController.text.trim();
    final wholesaleMinimumText = _wholesaleMinimumController.text.trim();
    final retailMaximumText = _retailMaximumController.text.trim();
    final quantityText = _quantityController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty || priceText.isEmpty || quantityText.isEmpty) {
      _showMessage('Please fill in name, price, and quantity.');
      return;
    }
    if (_category == null) {
      _showMessage('Please choose a category.');
      return;
    }
    final price = double.tryParse(priceText);
    final quantity = int.tryParse(quantityText);
    if (price == null || price <= 0) {
      _showMessage('Please enter a valid price.');
      return;
    }
    if (quantity == null || quantity < 0) {
      _showMessage('Please enter a valid quantity.');
      return;
    }
    final wholesalePrice = wholesalePriceText.isEmpty
        ? null
        : double.tryParse(wholesalePriceText);
    final wholesaleMinimum = int.tryParse(wholesaleMinimumText);
    final retailMaximum = int.tryParse(retailMaximumText);
    if (retailMaximum == null || retailMaximum < 1) {
      _showMessage('Please enter a valid retail maximum quantity.');
      return;
    }
    if (wholesalePriceText.isNotEmpty &&
        (wholesalePrice == null || wholesalePrice <= 0)) {
      _showMessage('Please enter a valid wholesale price.');
      return;
    }
    if (wholesalePrice != null &&
        (wholesaleMinimum == null || wholesaleMinimum < 2)) {
      _showMessage('Wholesale minimum quantity must be at least 2.');
      return;
    }

    setState(() => _loading = true);

    // Build the final image URL list (upload the new pick first, if any).
    final List<String> imageUrls = [];
    if (_file != null) {
      final url = await _cloudinaryService.uploadImage(_file!);
      if (url == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showMessage('Image upload failed. Check your internet and try again.');
        return;
      }
      imageUrls.add(url);
    } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      imageUrls.add(_imageUrl!);
    }

    final String? error;
    if (_isEditing) {
      error = await _productService.updateProduct(
        id: widget.productId!,
        name: name,
        category: _category!,
        price: price,
        quantity: quantity,
        description: description,
        wholesalePrice: wholesalePrice,
        wholesaleMinimumQuantity: wholesaleMinimum ?? 1,
        retailMaximumQuantity: retailMaximum,
        imageUrls: imageUrls,
        deliveryAvailable: _deliveryAvailable,
        pickupOnly: _pickupOnly,
      );
    } else {
      error = await _productService.addProduct(
        name: name,
        category: _category!,
        price: price,
        quantity: quantity,
        description: description,
        wholesalePrice: wholesalePrice,
        wholesaleMinimumQuantity: wholesaleMinimum ?? 1,
        retailMaximumQuantity: retailMaximum,
        imageUrls: imageUrls,
        deliveryAvailable: _deliveryAvailable,
        pickupOnly: _pickupOnly,
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      _showMessage(_isEditing ? 'Product updated!' : 'Product posted!');
      Navigator.pop(context);
    } else {
      _showMessage(error);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Product?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'This will permanently remove this product.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    final error = await _productService.deleteProduct(widget.productId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      _showMessage('Product deleted.');
      Navigator.pop(context);
    } else {
      _showMessage(error);
    }
  }

  Future<void> _toggleArchive() async {
    setState(() => _loading = true);
    final error = _isArchived
        ? await _productService.unarchiveProduct(widget.productId!)
        : await _productService.archiveProduct(widget.productId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      setState(() => _isArchived = !_isArchived);
      _showMessage(_isArchived
          ? 'Listing archived — hidden from the marketplace until you restore it.'
          : 'Listing restored — visible in the marketplace again.');
    } else {
      _showMessage(error);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _darkGreen,
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint, {
    IconData? icon,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.black38, fontSize: 13.5),
      prefixIcon: icon != null ? Icon(icon, color: _midGreen) : null,
      prefix: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _lightGreenAccent, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _lightGreenAccent, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _darkGreen, width: 1.6),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  // ---- Profile header ----
  Widget _profileHeader() {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Farmer';
    return Row(
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: _lightGreenAccent,
          child: Icon(Icons.person, color: _darkGreen, size: 26),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              'Farmer',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Single image slot ----
  Widget _imageSlot() {
    final hasImage =
        _bytes != null || (_imageUrl != null && _imageUrl!.isNotEmpty);

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: GestureDetector(
        onTap: _loading ? null : _pickImage,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _lightGreenBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _midGreen.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: !hasImage
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      size: 34,
                      color: _midGreen,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to take or choose a photo\nof your livestock or crops',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: _midGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'High-quality photos sell faster',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.grey[500],
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _bytes != null
                          ? Image.memory(_bytes!, fit: BoxFit.cover)
                          : Image.network(_imageUrl!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: _loading ? null : _removeImage,
                          tooltip: 'Remove photo',
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 16,
                          ),
                          onPressed: _loading ? null : _pickImage,
                          tooltip: 'Change photo',
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ==========================================================
  // AI-DRIVEN PRICE RECOMMENDATION — computed live from active
  // listings, completed sales, and the admin baseline price, via
  // PriceRecommendationService. See _computeRecommendation above.
  // ==========================================================
  Widget _priceRecommendation() {
    final typedName = _nameController.text.trim();

    if (typedName.isEmpty) {
      return _recoShell(
        child: Text(
          'Type a product title to see a price suggestion.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5),
        ),
      );
    }

    final match = _computeRecommendation(typedName);
    if (match == null) {
      return _recoShell(
        child: Text(
          'No market data yet for "$typedName" — no similar active listings, '
          'past sales, or admin baseline price found.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5),
        ),
      );
    }

    final median = match.median;
    final wholesaleSuggestion = median * 0.9;
    final low = match.low;
    final high = match.high;

    return _recoShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUGGESTED PRICE',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${median.toStringAsFixed(2)}/kg',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TYPICAL RANGE',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${low.toStringAsFixed(2)} to ₱${high.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Basis of Recommendation',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _basisLine(
            match.listingCount > 0 || match.transactionCount > 0
                ? 'Based on ${match.listingCount} active listing(s) and '
                    '${match.transactionCount} completed sale(s) for similar products.'
                : 'Based only on the admin-set baseline price — no matching '
                    'listings or sales yet.',
          ),
          if (match.hasBaseline)
            _basisLine(
              'Anchored to the official baseline price '
              '(₱${match.baselinePrice!.toStringAsFixed(2)}) set by AgriTrade+ admins.',
            ),
          _basisLine(
            'Suggested price is the median, so a single unusually high or low listing won\'t skew it.',
          ),
          _basisLine(
            'Range reflects how much sellers actually vary — tighter when they agree, wider when they don\'t.',
          ),
          if (match.limitedData)
            _basisLine(
              'Limited data so far — treat this as a rough starting point, '
              'not a confident market read.',
            ),
          const SizedBox(height: 10),
          Text(
            'Suggested wholesale price: ₱${wholesaleSuggestion.toStringAsFixed(2)}/kg (10% volume discount).',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Text(
            'This recommendation serves as a pricing guide only.',
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _priceController.text = median.toStringAsFixed(2);
                _showMessage('Suggested price applied.');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _darkGreen,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Apply Suggested Price',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recoShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_darkGreen, _midGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                'AI-Driven Price Recommendation',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _basisLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 6),
            child: Icon(Icons.check_circle, color: Colors.white70, size: 13),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Product' : 'Add Product',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: _darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isEditing) ...[
            IconButton(
              icon: Icon(_isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              tooltip: _isArchived ? 'Restore listing' : 'Archive listing',
              onPressed: _loading ? null : _toggleArchive,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _loading ? null : _delete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _profileHeader(),
            if (_isArchived) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 18, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This listing is archived and hidden from the marketplace.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),

            // ---- Single photo slot ----
            _imageSlot(),
            const SizedBox(height: 20),

            _label('Product Title'),
            TextField(
              controller: _nameController,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _inputDecoration('e.g., Premium Free-Range Chicken'),
            ),
            const SizedBox(height: 8),

            // ---- Category + Quantity side by side ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Category'),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        style: GoogleFonts.inter(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        decoration: _inputDecoration('Select...'),
                        hint: Text(
                          'Select...',
                          style: GoogleFonts.inter(
                            color: Colors.black38,
                            fontSize: 13.5,
                          ),
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: GoogleFonts.inter(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Quantity/Weight'),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: _inputDecoration('e.g., 50 kg'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ---- AI price recommendation (by product name) ----
            _priceRecommendation(),
            const SizedBox(height: 18),

            // ---- Price ----
            _label('Price'),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: _inputDecoration(
                '0.00',
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '₱',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkGreen,
                    ),
                  ),
                ),
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    'Php / kg',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            _label('Wholesale Price (Optional)'),
            TextField(
              controller: _wholesalePriceController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: _inputDecoration(
                'Leave blank to offer retail only',
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '₱',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkGreen,
                    ),
                  ),
                ),
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    'Php / kg',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _label('Wholesale Minimum Quantity'),
            TextField(
              controller: _wholesaleMinimumController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _inputDecoration('e.g., 10 kg'),
            ),
            const SizedBox(height: 12),

            // ---- Description ----
            _label('Description'),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _inputDecoration(
                'Tell buyers about how it was raised or grown...',
              ),
            ),
            const SizedBox(height: 8),

            // ---- Toggles ----
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Delivery Available',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              activeThumbColor: _darkGreen,
              value: _deliveryAvailable,
              onChanged: (v) => setState(() => _deliveryAvailable = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Pick-up Only',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              activeThumbColor: _darkGreen,
              value: _pickupOnly,
              onChanged: (v) => setState(() => _pickupOnly = v),
            ),
            const SizedBox(height: 16),

            // ---- Post ----
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkGreen,
                disabledBackgroundColor: Colors.grey.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
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
                      _isEditing ? 'Update' : 'Post',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
