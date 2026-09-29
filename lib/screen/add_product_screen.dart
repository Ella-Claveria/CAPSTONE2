import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/product_service.dart';
import '../services/cloudinary_service.dart';
import '../services/price_recommendation_service.dart';
import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import 'supported_products_screen.dart';

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
  static const Color _lightGreenBg = Colors.white;
  static const Color _lightGreenAccent = Color(0xFFDCEDC8);

  final _nameController = TextEditingController();
  // Autocomplete requires focusNode and textEditingController to be either
  // both null or both set — passing only the controller trips its
  // "textEditingController and focusNode must be provided" assertion.
  final _nameFocusNode = FocusNode();
  final _priceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _wholesaleMinimumController = TextEditingController(text: '10');
  final _quantityController = TextEditingController();
  final _descriptionController = TextEditingController();

  final ProductService _productService = ProductService();
  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  String? _category;
  // Derived from the Commodity Master List so this always has every category
  // the admin's approved commodities actually use (Grains, Root Crops,
  // Vegetables, Spices, Fruits, Livestock, Fisheries) — never a separately
  // hand-maintained list that can drift out of sync.
  final List<String> _categories = kCommodityMasterList.keys.toList();

  // Tracks the category we last auto-filled, so a farmer's own manual pick
  // is never silently overwritten — see _onNameChanged below.
  String? _lastAutoDetectedCategory;

  // The official Commodity Master List entry this listing represents (see
  // commodity_master_list.dart) — optional, separate from the free-text
  // Product Title/Category above, and used only to drive the AI-Assisted
  // Price Recommendation below. Never shown to buyers, never restricts
  // what the farmer can actually list.
  String? _selectedCommodity;

  bool _deliveryAvailable = false;
  bool _pickupOnly = false;
  bool _wholesaleEnabled = false;
  bool _loading = false;
  bool _isArchived = false;

  // Single photo slot. Holds either a freshly-picked file (+ preview bytes)
  // or an existing URL (when editing).
  XFile? _file;
  Uint8List? _bytes;
  String? _imageUrl;

  bool get _isEditing => widget.productId != null;

  // ==========================================================
  // LIVE MARKET DATA — active listings, completed sales, buyer search
  // activity, and the admin-set reference price, kept in sync via
  // Firestore streams and fed into PriceRecommendationService. See
  // _matchedCommodity/_computeRecommendation.
  // ==========================================================
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _liveProducts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _completedOrders = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _marketPrices = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchEvents = [];
  StreamSubscription? _productsSub;
  StreamSubscription? _ordersSub;
  StreamSubscription? _marketPricesSub;
  StreamSubscription? _searchEventsSub;

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
    // Aggregated only — see PriceRecommendation.searchCount's doc comment;
    // no individual buyer/search record is ever surfaced to the farmer.
    _searchEventsSub = FirebaseFirestore.instance
        .collection('searchEvents')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _searchEvents = snap.docs);
    });
  }

  double? _numField(Map<String, dynamic> data, String field) {
    final raw = data[field];
    if (raw is num) return raw.toDouble();
    return num.tryParse(raw?.toString() ?? '')?.toDouble();
  }

  DateTime? _dateField(Map<String, dynamic> data, String field) {
    final raw = data[field];
    return raw is Timestamp ? raw.toDate() : null;
  }

  // The commodity this listing represents, for price-recommendation
  // purposes only: the explicit dropdown pick wins when set; otherwise
  // fall back to matching the free-text Product Title against the
  // official master list (commodity_master_list.dart). Null means this
  // listing isn't (yet) recognizable as one of the supported commodities
  // — the price panel shows the "not supported" message in that case,
  // never a guessed number (client requirement: supported commodities
  // only).
  String? get _matchedCommodity =>
      _selectedCommodity ?? matchSupportedCommodity(_nameController.text.trim());

  // The Unit of Measurement for the currently-selected commodity (see
  // commodity_master_list.dart's kCommodityUnits) — drives the Available
  // Stock / Price per Unit labels below and updates immediately whenever
  // _matchedCommodity changes, since both read straight from this getter
  // on every rebuild rather than caching a stale value.
  String get _currentUnit => unitForCommodity(_matchedCommodity ?? '');
  bool get _isCountBasedUnit => isCountBasedUnit(_currentUnit);

  PriceRecommendation _computeRecommendation(
    String commodity, {
    String pricingType = 'retail',
  }) {
    final now = DateTime.now();
    final isWholesale = pricingType == 'wholesale';

    final listingPrices = <double>[];
    num supplyQuantity = 0;
    for (final doc in _liveProducts) {
      if (widget.productId != null && doc.id == widget.productId) continue;
      final data = doc.data();
      if (data['isArchived'] == true || data['isSuspended'] == true) continue;
      final quantity = _numField(data, 'quantity') ?? 0;
      if (quantity <= 0) continue;
      final matchesCommodity =
          (data['commodity']?.toString().toLowerCase() == commodity.toLowerCase()) ||
              PriceRecommendationService.namesLikelyMatch(
                commodity,
                (data['name'] ?? '').toString(),
              );
      if (!matchesCommodity) continue;

      double? price;
      if (isWholesale) {
        final wholesale = _numField(data, 'wholesalePrice');
        final enabled = data['wholesaleEnabled'] == true ||
            (data['wholesaleEnabled'] == null && wholesale != null && wholesale > 0);
        if (!enabled) continue;
        price = wholesale;
      } else {
        price = _numField(data, 'retailPrice') ?? _numField(data, 'price');
      }

      if (price != null && price > 0) {
        listingPrices.add(price);
        supplyQuantity += quantity;
      }
    }

    final transactions = <({double price, DateTime? date})>[];
    for (final doc in _completedOrders) {
      final data = doc.data();
      if (!PriceRecommendationService.namesLikelyMatch(
        commodity,
        (data['productName'] ?? '').toString(),
      )) {
        continue;
      }

      final storedType = (data['pricingType'] ?? 'retail').toString().toLowerCase();
      if (isWholesale ? storedType != 'wholesale' : storedType == 'wholesale') {
        continue;
      }

      final price =
          _numField(data, 'pricePerUnit') ?? _numField(data, 'unitPrice');
      if (price != null && price > 0) {
        transactions.add((
          price: price,
          date: _dateField(data, 'completedAt') ?? _dateField(data, 'createdAt'),
        ));
      }
    }

    // General product searches are a useful retail demand signal, but they
    // do not prove bulk/wholesale intent. Wholesale recommendations therefore
    // rely on real wholesale listings/transactions unless a dedicated bulk
    // demand signal is introduced later.
    var searchCount30d = 0;
    if (!isWholesale) {
      for (final doc in _searchEvents) {
        final data = doc.data();
        final query = (data['query'] ?? '').toString();
        if (query.trim().isEmpty) continue;
        if (!PriceRecommendationService.namesLikelyMatch(commodity, query)) {
          continue;
        }
        final date = _dateField(data, 'createdAt');
        if (date != null &&
            now.difference(date) <=
                PriceRecommendationService.recentDemandWindow) {
          searchCount30d++;
        }
      }
    }

    double? referencePrice;
    DateTime? referenceEffectiveDate;
    for (final doc in _marketPrices) {
      final data = doc.data();
      if (!PriceRecommendationService.namesLikelyMatch(
        commodity,
        (data['name'] ?? '').toString(),
      )) {
        continue;
      }

      // A wholesale reference is used only when the agricultural office
      // explicitly supplied one. Never derive it by discounting retail.
      final price = isWholesale
          ? _numField(data, 'wholesaleBaselinePrice')
          : _numField(data, 'baselinePrice');
      if (price != null && price > 0) {
        referencePrice = price;
        referenceEffectiveDate =
            _dateField(data, 'effectiveDate') ?? _dateField(data, 'updatedAt');
        break;
      }
    }

    return PriceRecommendationService.recommend(
      listingPrices: listingPrices,
      transactions: transactions,
      reference: PriceRecommendationService.referenceInfo(
        price: referencePrice,
        effectiveDate: referenceEffectiveDate,
        now: now,
      ),
      supplyQuantity: supplyQuantity > 0 ? supplyQuantity.toDouble() : null,
      searchCount30d: searchCount30d,
      now: now,
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
      final existingWholesale = (data['wholesalePrice'] as num?)?.toDouble();
      _wholesaleEnabled = data['wholesaleEnabled'] == true ||
          (data['wholesaleEnabled'] == null && existingWholesale != null && existingWholesale > 0);
      _quantityController.text = (data['quantity'] as num?)?.toString() ?? '';
      _descriptionController.text = data['description']?.toString() ?? '';
      final category = data['category']?.toString();
      if (category != null && _categories.contains(category)) {
        _category = category;
      }
      final commodity = data['commodity']?.toString();
      if (commodity != null && kSupportedCommodities.contains(commodity)) {
        _selectedCommodity = commodity;
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
    // Rebuild the price suggestion as the user types, and auto-detect the
    // category (see _onNameChanged) — the product name IS the commodity now.
    _nameController.addListener(_onNameChanged);
    _listenToMarketData();
  }

  // Product Name now doubles as the commodity picker (it's restricted to
  // the Commodity Master List — see _save()'s unsupported-product gate), so
  // as soon as it resolves to a supported commodity, auto-fill Category to
  // match. Only touches Category while it's still showing our own last
  // suggestion (or is empty) — a farmer's own manual pick is never
  // silently overwritten.
  void _onNameChanged() {
    final matched = matchSupportedCommodity(_nameController.text.trim());
    if (matched != null) {
      final detected = categoryOfCommodity(matched);
      if (detected != null &&
          _categories.contains(detected) &&
          (_category == null || _category == _lastAutoDetectedCategory)) {
        _category = detected;
        _lastAutoDetectedCategory = detected;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _ordersSub?.cancel();
    _marketPricesSub?.cancel();
    _searchEventsSub?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _priceController.dispose();
    _wholesalePriceController.dispose();
    _wholesaleMinimumController.dispose();
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
                  style: GoogleFonts.montserrat(
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
                style: GoogleFonts.montserrat(
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
                style: GoogleFonts.montserrat(
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
    final quantityText = _quantityController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty || priceText.isEmpty || quantityText.isEmpty) {
      _showMessage('Please fill in name, price, and quantity.');
      return;
    }
    // Product Title must resolve to one of AgriTrade+'s supported
    // commodities (see commodity_master_list.dart) — never a fabricated or
    // unsupported listing. The autocomplete field below normally already
    // fills in an exact supported name; this is the hard gate for anyone
    // who typed past it instead of picking a suggestion.
    if (matchSupportedCommodity(name) == null) {
      _showUnsupportedProductDialog();
      return;
    }
    if (_category == null) {
      _showMessage('Please choose a category.');
      return;
    }
    final price = double.tryParse(priceText);
    final quantity = num.tryParse(quantityText);
    if (price == null || price <= 0) {
      _showMessage('Please enter a valid price.');
      return;
    }
    if (quantity == null || quantity < 0) {
      _showMessage('Please enter a valid, non-negative available stock.');
      return;
    }
    final unit = _currentUnit;
    if (isCountBasedUnit(unit) && quantity != quantity.roundToDouble()) {
      _showMessage('Available Stock for $unit must be a whole number.');
      return;
    }
    final wholesalePrice = !_wholesaleEnabled || wholesalePriceText.isEmpty
        ? null
        : double.tryParse(wholesalePriceText);
    final wholesaleMinimum = !_wholesaleEnabled
        ? null
        : num.tryParse(wholesaleMinimumText);
    if (_wholesaleEnabled && (wholesalePrice == null || wholesalePrice <= 0)) {
      _showMessage('Please enter a valid wholesale price.');
      return;
    }
    if (_wholesaleEnabled && wholesalePrice! >= price) {
      _showMessage('Wholesale price must be lower than the retail price.');
      return;
    }
    if (_wholesaleEnabled &&
        (wholesaleMinimum == null || wholesaleMinimum <= 0)) {
      _showMessage('Please enter a valid wholesale minimum quantity.');
      return;
    }
    if (_wholesaleEnabled &&
        isCountBasedUnit(unit) &&
        wholesaleMinimum != wholesaleMinimum.roundToDouble()) {
      _showMessage('Wholesale minimum quantity for $unit must be a whole number.');
      return;
    }
    if (_wholesaleEnabled && wholesaleMinimum! > quantity) {
      _showMessage('Wholesale minimum cannot be greater than the available stock.');
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
        wholesaleEnabled: _wholesaleEnabled,
        wholesalePrice: wholesalePrice,
        wholesaleMinimumQuantity: wholesaleMinimum ?? 1,
        imageUrls: imageUrls,
        deliveryAvailable: _deliveryAvailable,
        pickupOnly: _pickupOnly,
        commodity: _selectedCommodity,
        unit: unit,
      );
    } else {
      error = await _productService.addProduct(
        name: name,
        category: _category!,
        price: price,
        quantity: quantity,
        description: description,
        wholesaleEnabled: _wholesaleEnabled,
        wholesalePrice: wholesalePrice,
        wholesaleMinimumQuantity: wholesaleMinimum ?? 1,
        imageUrls: imageUrls,
        deliveryAvailable: _deliveryAvailable,
        pickupOnly: _pickupOnly,
        commodity: _selectedCommodity,
        unit: unit,
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
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'This will permanently remove this product.',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.montserrat(color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.montserrat(
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
          style: GoogleFonts.montserrat(color: Colors.white),
        ),
      ),
    );
  }

  void _openSupportedProducts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SupportedProductsScreen()),
    );
  }

  // Shown instead of creating the listing when the Product Title doesn't
  // resolve to any commodity on the Commodity Master List (see _save()).
  Future<void> _showUnsupportedProductDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Product not currently supported',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16)),
        content: Text(
          'AgriTrade+ currently supports selected commodities based on the system '
          'scope and available agricultural data. Please choose a product from the '
          'Supported Products list.',
          style: GoogleFonts.montserrat(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openSupportedProducts();
            },
            child: Text('View Supported Products',
                style: GoogleFonts.montserrat(color: _darkGreen, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.montserrat(color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  // Small, always-visible warning (not a modal) that not every product can
  // be sold on AgriTrade+ — the full explanation lives in Farmer setup (see
  // register_screen.dart's Supported Products section).
  Widget _supportedProductsBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not all goods are available to sell. AgriTrade+ currently supports '
                  'selected commodities only — choose a product from the supported list.',
                  style: GoogleFonts.montserrat(fontSize: 11.5, color: Colors.black87, height: 1.35),
                ),
                GestureDetector(
                  onTap: _openSupportedProducts,
                  child: Text(
                    'View Supported Products',
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      color: _darkGreen,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Read-only — the unit is controlled entirely by the selected commodity
  // (see commodity_master_list.dart's kCommodityUnits), never typed by the
  // farmer, and updates immediately whenever _matchedCommodity changes
  // since this just reads _currentUnit fresh on every rebuild.
  Widget _unitOfMeasurementDisplay() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.straighten, size: 16, color: _midGreen),
          const SizedBox(width: 6),
          Text('Unit of Measurement: ', style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.grey[700])),
          Text(_currentUnit,
              style: GoogleFonts.montserrat(fontSize: 12.5, fontWeight: FontWeight.bold, color: _darkGreen)),
        ],
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
      hintStyle: GoogleFonts.montserrat(color: Colors.black38, fontSize: 13.5),
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
        style: GoogleFonts.montserrat(
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
              style: GoogleFonts.montserrat(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              'Farmer',
              style: GoogleFonts.montserrat(
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
                      style: GoogleFonts.montserrat(
                        color: _midGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'High-quality photos sell faster',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
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
  // AI-ASSISTED PRICE RECOMMENDATION — a statistical/rule-based blend of
  // the admin reference price, recent completed transactions, active
  // listings, supply, and buyer demand (see PriceRecommendationService) —
  // NOT a trained machine-learning model, so it's never called that in the
  // UI. Gated to the official Commodity Master List
  // (commodity_master_list.dart) per the agricultural client's approved
  // scope — an unsupported/unrecognized product gets an explicit message
  // instead of a guessed number. Advisory only: nothing here ever touches
  // the Price field until the farmer taps "Use Suggested Price" below.
  // ==========================================================
  Widget _priceRecommendation() {
    final typedName = _nameController.text.trim();
    final commodity = _matchedCommodity;

    if (typedName.isEmpty && _selectedCommodity == null) {
      return _recoShell(
        child: Text(
          'Type a product name above to see a price suggestion.',
          style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12.5),
        ),
      );
    }

    if (commodity == null) {
      return _recoShell(
        child: Text(
          'AI-assisted price recommendations are only available for AgriTrade+\'s supported '
          'commodities (see Supported Products above) — "$typedName" isn\'t recognized as one yet.',
          style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12.5),
        ),
      );
    }

    final result = _computeRecommendation(commodity);

    // No admin reference price AND no marketplace data at all — never a
    // fabricated number (req: "Do not invent missing data").
    if (result.tier == PriceDataTier.insufficient) {
      return _recoShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price recommendation currently unavailable',
              style: GoogleFonts.montserrat(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Not enough pricing data is available for this commodity yet. Please check again after '
              'the latest reference price has been provided or more marketplace data becomes available.',
              style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'You can still set your own selling price below.',
              style: GoogleFonts.montserrat(color: Colors.white60, fontSize: 10.5, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    // From here on (referenceOnly / limited / full), a suggested price
    // always exists — referenceOnly's IS the reference price itself, with
    // a small fixed cushion (PriceRecommendationService.coldStartRangePct)
    // rather than a guessed spread. Cold start (Level 1) and a maturing
    // marketplace (Levels 2-4) share this same layout; only which pieces
    // have real data to show differs.
    final suggested = result.suggestedPrice!;
    final isColdStart = result.tier == PriceDataTier.referenceOnly;

    return _recoShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _statBlock('SUGGESTED PRICE', '₱${suggested.toStringAsFixed(2)} / $_currentUnit', big: true)),
              Container(width: 1, height: 38, color: Colors.white24),
              const SizedBox(width: 14),
              Expanded(
                child: _statBlock(
                  'SUGGESTED RANGE',
                  '₱${result.suggestedLow!.toStringAsFixed(2)} – ₱${result.suggestedHigh!.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  'REFERENCE PRICE',
                  result.referencePrice != null ? '₱${result.referencePrice!.toStringAsFixed(2)} / $_currentUnit' : 'Not set',
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white24),
              const SizedBox(width: 14),
              Expanded(
                child: _statBlock(
                  'MARKETPLACE RANGE',
                  result.marketplaceLow != null
                      ? '₱${result.marketplaceLow!.toStringAsFixed(2)} – ₱${result.marketplaceHigh!.toStringAsFixed(2)}'
                      : 'No active listings yet',
                ),
              ),
            ],
          ),
          if (result.referenceEffectiveDate != null) ...[
            const SizedBox(height: 6),
            Text(
              'Reference price last updated: ${DateFormat('MMM d, y').format(result.referenceEffectiveDate!)}'
              '${result.referenceIsStale ? ' (may be outdated)' : ''}',
              style: GoogleFonts.montserrat(color: Colors.white60, fontSize: 10.5),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Data Availability: ${result.tier.dataAvailabilityLabel}',
              style: GoogleFonts.montserrat(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isColdStart
                ? 'This recommendation is currently based mainly on the latest reference commodity price. '
                    'Future recommendations will improve as AgriTrade+ collects more actual marketplace activity.'
                : 'Based on the latest reference price, recent completed transactions, active listings, and '
                    'current AgriTrade+ marketplace activity.',
            style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            'Based on:',
            style: GoogleFonts.montserrat(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (result.referencePrice != null)
            _basisLine(result.referenceIsStale
                ? 'Latest reference commodity price (last updated a while ago)'
                : 'Latest reference commodity price'),
          if (result.transactionCount > 0) _basisLine('${result.transactionCount} recent completed transaction(s)'),
          if (result.listingCount > 0) _basisLine('${result.listingCount} active listing(s)'),
          if (result.usedSupplyDemand) _basisLine('Current supply and buyer demand'),
          if (isColdStart)
            _basisLine('AgriTrade+ does not yet have enough marketplace transaction data for this product.')
          else
            _basisLine('Weighted toward actual completed sales over asking prices, and outlier-resistant.'),
          if (result.tier == PriceDataTier.limited)
            _basisLine('Limited data so far — treat this as a rough starting point, not a confident market read.'),
          if (_wholesaleEnabled) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withValues(alpha: 0.28)),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final wholesaleResult =
                    _computeRecommendation(commodity, pricingType: 'wholesale');
                if (wholesaleResult.tier == PriceDataTier.insufficient) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHOLESALE PRICE RECOMMENDATION',
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Wholesale price recommendation currently unavailable due to limited wholesale market data.',
                        style: GoogleFonts.montserrat(
                          color: Colors.white70,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You can set the wholesale price manually. AgriTrade+ will not create a discount or wholesale reference price automatically.',
                        style: GoogleFonts.montserrat(
                          color: Colors.white60,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  );
                }

                final wholesaleSuggested = wholesaleResult.suggestedPrice!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WHOLESALE SUGGESTED PRICE',
                      style: GoogleFonts.montserrat(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${wholesaleSuggested.toStringAsFixed(2)} / $_currentUnit',
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      wholesaleResult.referencePrice != null
                          ? 'Based only on wholesale-specific reference/market data.'
                          : 'Based on actual wholesale listings and completed wholesale transactions.',
                      style: GoogleFonts.montserrat(
                        color: Colors.white60,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        _wholesalePriceController.text =
                            wholesaleSuggested.toStringAsFixed(2);
                        _showMessage(
                          'Wholesale suggested price applied — you can still edit it.',
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      child: const Text('Use Wholesale Suggested Price'),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'This is an AI-assisted suggestion only — you always make the final pricing decision.',
            style: GoogleFonts.montserrat(color: Colors.white60, fontSize: 10.5, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _priceController.text = suggested.toStringAsFixed(2);
                _showMessage('Suggested price applied — you can still edit it.');
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
                'Use Suggested Price',
                style: GoogleFonts.montserrat(
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

  Widget _statBlock(String label, String value, {bool big = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontSize: big ? 18 : 14.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
                'AI-Assisted Price Recommendation',
                style: GoogleFonts.montserrat(
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
              style: GoogleFonts.montserrat(
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
          style: GoogleFonts.montserrat(
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
                        style: GoogleFonts.montserrat(fontSize: 12, color: Colors.orange[900]),
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

            _label('Product Name'),
            Autocomplete<String>(
              textEditingController: _nameController,
              focusNode: _nameFocusNode,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return kSupportedCommodities;
                return kSupportedCommodities.where((c) => c.toLowerCase().contains(query));
              },
              onSelected: (selection) => setState(() => _selectedCommodity = selection),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: GoogleFonts.montserrat(fontSize: 14),
                  decoration: _inputDecoration('e.g., Eggplant'),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 340),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(option, style: GoogleFonts.montserrat(fontSize: 13.5)),
                            subtitle: Text(categoryOfCommodity(option) ?? '',
                                style: GoogleFonts.montserrat(fontSize: 10.5, color: Colors.grey[600])),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Start typing to pick a supported product (e.g., "egg" suggests "Eggplant").',
              style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            _supportedProductsBanner(),
            const SizedBox(height: 8),
            if (_matchedCommodity != null) _unitOfMeasurementDisplay(),

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
                        style: GoogleFonts.montserrat(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        decoration: _inputDecoration('Select...'),
                        hint: Text(
                          'Select...',
                          style: GoogleFonts.montserrat(
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
                                  style: GoogleFonts.montserrat(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _category = value;
                          // A deliberate manual pick — stop auto-detect from
                          // overwriting it until the product name changes to
                          // a different supported commodity.
                          _lastAutoDetectedCategory = null;
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Available Stock ($_currentUnit)'),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.numberWithOptions(decimal: !_isCountBasedUnit),
                        style: GoogleFonts.montserrat(fontSize: 14),
                        decoration: _inputDecoration('e.g., 50', suffix: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Text(_currentUnit,
                              style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.grey[600])),
                        )),
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
            _label(pricePerUnitLabel(_currentUnit)),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: _inputDecoration(
                '0.00',
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '₱',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _darkGreen,
                    ),
                  ),
                ),
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    'Php / $_currentUnit',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Offer Wholesale',
                style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Set a lower bulk price once the buyer reaches your minimum quantity.',
                style: GoogleFonts.montserrat(fontSize: 11.5, color: Colors.grey[600]),
              ),
              activeThumbColor: _darkGreen,
              value: _wholesaleEnabled,
              onChanged: (value) => setState(() {
                _wholesaleEnabled = value;
                if (!value) _wholesalePriceController.clear();
              }),
            ),
            if (_wholesaleEnabled) ...[
              const SizedBox(height: 4),
              _label('Wholesale ${pricePerUnitLabel(_currentUnit)}'),
              TextField(
                controller: _wholesalePriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w600),
                decoration: _inputDecoration(
                  '0.00',
                  prefix: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '₱',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _darkGreen,
                      ),
                    ),
                  ),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text(
                      'Php / $_currentUnit',
                      style: GoogleFonts.montserrat(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _label('Minimum Wholesale Quantity ($_currentUnit)'),
              TextField(
                controller: _wholesaleMinimumController,
                keyboardType: TextInputType.numberWithOptions(decimal: !_isCountBasedUnit),
                style: GoogleFonts.montserrat(fontSize: 14),
                decoration: _inputDecoration(
                  'e.g., 20',
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Text(
                      _currentUnit,
                      style: GoogleFonts.montserrat(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ---- Description ----
            _label('Description'),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: GoogleFonts.montserrat(fontSize: 14),
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
                style: GoogleFonts.montserrat(
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
                style: GoogleFonts.montserrat(
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
                      style: GoogleFonts.montserrat(
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
