import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/product_service.dart';
import '../services/cloudinary_service.dart';
import '../services/delivery_coverage.dart';
import '../services/harvest_info.dart';
import '../services/price_deviation.dart';
import '../services/price_recommendation_service.dart';
import '../data/commodity_master_list.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/delivery_area_picker.dart';
import '../widgets/profile_avatar.dart';
import 'supported_products_screen.dart';

class AddProductScreen extends StatefulWidget {
  final String? productId;
  final Map<String, dynamic>? existingData;

  const AddProductScreen({super.key, this.productId, this.existingData});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  // The login button's dark green (AppTheme.dark), used for the header, the
  // Post button and every other green on this screen; the only other green
  // here is the pale tint (_lightGreenAccent).
  static const Color _darkGreen = AppTheme.dark;
  static const Color _lightGreenBg = Colors.white;
  static const Color _lightGreenAccent = Color(0xFFDCEDC8);

  final _nameController = TextEditingController();
  // Autocomplete requires focusNode and textEditingController to be either
  // both null or both set — passing only the controller trips its
  // "textEditingController and focusNode must be provided" assertion.
  final _nameFocusNode = FocusNode();
  // Leaving a price field is what triggers its price warning (see
  // _checkPrice) — not every keystroke.
  final _priceFocusNode = FocusNode();
  final _wholesalePriceFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();
  final _wholesaleMinFocusNode = FocusNode();

  // Scroll targets for validation errors (see _showErrorAt).
  final _photoKey = GlobalKey();
  final _nameKey = GlobalKey();
  final _stockKey = GlobalKey();
  final _priceKey = GlobalKey();
  final _wholesalePriceKey = GlobalKey();
  final _wholesaleMinKey = GlobalKey();

  // Switched on by the first Post tap that finds a problem; from then on
  // the first invalid field (_issue, refreshed every build) is outlined in
  // red with its message under it, updating live as the farmer fixes it.
  bool _showValidation = false;
  _FormIssue? _issue;

  _FormIssue? get _shownIssue => _showValidation ? _issue : null;

  // The last price each warning was evaluated for (see _checkPrice).
  double? _checkedRetailPrice;
  double? _checkedWholesalePrice;

  // What the farmer already answered "Post Anyway" to, so the same
  // warning isn't shown again unless the price changes meaningfully.
  ({double price, PriceDeviationLevel level})? _confirmedRetail;
  ({double price, PriceDeviationLevel level})? _confirmedWholesale;
  final _priceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _wholesaleMinimumController = TextEditingController(text: '10');
  final _quantityController = TextEditingController();
  final _descriptionController = TextEditingController();

  final ProductService _productService = ProductService();
  final ImagePicker _imagePicker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  String? _category;

  // When the current batch was harvested, as entered by the farmer (see
  // harvest_info.dart). Only offered for produce categories.
  DateTime? _harvestDate;

  // The official Commodity Master List entry this listing represents (see
  // commodity_master_list.dart) — optional, separate from the free-text
  // Product Title/Category above, and used only to drive the AI-Assisted
  // Price Recommendation below. Never shown to buyers, never restricts
  // what the farmer can actually list.
  String? _selectedCommodity;

  bool _deliveryAvailable = false;
  // Stored as 'pickupOnly' for compatibility, but it has always meant
  // "pick-up is available" wherever it's read.
  bool _pickupOnly = false;

  // Delivery coverage — required once Delivery Available is on (see
  // delivery_coverage.dart). Null until the farmer chooses.
  DeliveryCoverageType? _coverageType;
  List<DeliveryArea> _customAreas = [];
  DeliveryFeeType? _feeType;
  final _deliveryFeeController = TextEditingController();
  final _deliveryFeeFocusNode = FocusNode();
  final _coverageKey = GlobalKey();
  final _deliveryFeeKey = GlobalKey();
  // The farm's own barangay/municipality, from the farmer's profile.
  String _farmBarangay = '';
  DeliveryArea _farmOrigin = kDefaultFarmOrigin;
  bool _wholesaleEnabled = false;
  bool _loading = false;
  bool _isArchived = false;
  bool _confirmingExit = false;
  bool _allowPop = false;

  // Single photo slot. Holds either a freshly-picked file (+ preview bytes)
  // or an existing URL (when editing).
  XFile? _file;
  Uint8List? _bytes;
  String? _imageUrl;

  bool get _isEditing => widget.productId != null;

  bool get _hasImage =>
      _bytes != null || (_imageUrl != null && _imageUrl!.isNotEmpty);

  // Live, so a profile photo/name change shows up in the header here too.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream =
      FirebaseAuth.instance.currentUser == null
      ? null
      : FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .snapshots();

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
      _selectedCommodity ??
      matchSupportedCommodity(_nameController.text.trim());

  // The Unit of Measurement for the currently-selected commodity (see
  // commodity_master_list.dart's CommodityRegistry) — drives the Available
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
          (data['commodity']?.toString().toLowerCase() ==
              commodity.toLowerCase()) ||
          PriceRecommendationService.namesLikelyMatch(
            commodity,
            (data['name'] ?? '').toString(),
          );
      if (!matchesCommodity) continue;
      final listingUnit = (data['unit'] ?? '').toString().trim();
      if (listingUnit.isNotEmpty && listingUnit != _currentUnit) continue;

      double? price;
      if (isWholesale) {
        final wholesale = _numField(data, 'wholesalePrice');
        final enabled =
            data['wholesaleEnabled'] == true ||
            (data['wholesaleEnabled'] == null &&
                wholesale != null &&
                wholesale > 0);
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

      final storedType = (data['pricingType'] ?? 'retail')
          .toString()
          .toLowerCase();
      if (isWholesale ? storedType != 'wholesale' : storedType == 'wholesale') {
        continue;
      }
      final transactionUnit = (data['unit'] ?? '').toString().trim();
      if (transactionUnit.isNotEmpty && transactionUnit != _currentUnit) {
        continue;
      }

      final price =
          _numField(data, 'pricePerUnit') ?? _numField(data, 'unitPrice');
      if (price != null && price > 0) {
        transactions.add((
          price: price,
          date:
              _dateField(data, 'completedAt') ?? _dateField(data, 'createdAt'),
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
      _wholesaleEnabled =
          data['wholesaleEnabled'] == true ||
          (data['wholesaleEnabled'] == null &&
              existingWholesale != null &&
              existingWholesale > 0);
      _quantityController.text = (data['quantity'] as num?)?.toString() ?? '';
      _descriptionController.text = data['description']?.toString() ?? '';
      final harvested = data['harvestDate'];
      if (harvested is Timestamp) _harvestDate = harvested.toDate();
      final category = data['category']?.toString();
      final commodity = data['commodity']?.toString();
      if (commodity != null &&
          CommodityRegistry.instance.find(commodity) != null) {
        _selectedCommodity = commodity;
      }
      _category =
          categoryOfCommodity(
            matchSupportedCommodity(_nameController.text.trim()) ?? '',
          ) ??
          category;
      _deliveryAvailable = data['deliveryAvailable'] == true;
      _pickupOnly = data['pickupOnly'] == true;
      // Listings saved before coverage existed leave these unset, so the
      // farmer is asked to choose them on the next save.
      if (data['deliveryCoverage'] is Map) {
        final coverage = DeliveryCoverage.fromProduct(data);
        _coverageType = coverage.type;
        _customAreas = [...coverage.customAreas];
        _feeType = coverage.feeType;
        if (coverage.feeKnown) {
          _deliveryFeeController.text = _plainNumber(coverage.fee!);
        }
      }
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
    // Admin changes to the commodity list (added, moved, disabled) apply
    // to the suggestions and the category right away.
    CommodityRegistry.instance.addListener(_onCommoditiesChanged);
    // Keeps the Post button's enabled look and the red highlights in step
    // with what's typed (see _formIssue).
    for (final controller in [
      _quantityController,
      _priceController,
      _wholesalePriceController,
      _wholesaleMinimumController,
      _deliveryFeeController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
    _loadFarmOrigin();
    _listenToMarketData();

    // An existing listing's prices count as already checked, so their
    // notes show as soon as the market data arrives.
    _checkedRetailPrice = double.tryParse(_priceController.text.trim());
    _checkedWholesalePrice = double.tryParse(
      _wholesalePriceController.text.trim(),
    );
    _priceFocusNode.addListener(() {
      if (!_priceFocusNode.hasFocus) _checkPrice(wholesale: false);
    });
    _wholesalePriceFocusNode.addListener(() {
      if (!_wholesalePriceFocusNode.hasFocus) _checkPrice(wholesale: true);
    });
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  // Same Barangay / Within Municipality are measured from the farm.
  Future<void> _loadFarmOrigin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null || !mounted) return;
      final municipality = (data['municipality'] ?? '').toString().trim();
      setState(() {
        _farmBarangay = (data['barangay'] ?? '').toString().trim();
        if (municipality.isNotEmpty) {
          _farmOrigin = DeliveryArea(
            municipality,
            (data['province'] ?? '').toString().trim(),
          );
        }
      });
    } catch (_) {
      // Falls back to Laurel, Batangas — where every farmer registers.
    }
  }

  String _plainNumber(num value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  DeliveryCoverage? get _deliveryCoverage {
    final type = _coverageType;
    final feeType = _feeType;
    if (!_deliveryAvailable || type == null || feeType == null) return null;
    return DeliveryCoverage(
      type: type,
      customAreas: _customAreas,
      feeType: feeType,
      fee: feeType == DeliveryFeeType.fixed
          ? num.tryParse(_deliveryFeeController.text.trim())
          : null,
      originBarangay: _farmBarangay,
      origin: _farmOrigin,
    );
  }

  // Category is always derived from the current product name; it cannot be
  // independently changed by the farmer.
  void _onNameChanged() {
    final name = _nameController.text.trim();
    if (_selectedCommodity != null &&
        _selectedCommodity!.toLowerCase() != name.toLowerCase()) {
      _selectedCommodity = null;
    }
    final matched = matchSupportedCommodity(name);
    _category = matched == null ? null : categoryOfCommodity(matched);
    setState(() {});
  }

  void _onCommoditiesChanged() {
    if (mounted) _onNameChanged();
  }

  @override
  void dispose() {
    CommodityRegistry.instance.removeListener(_onCommoditiesChanged);
    _productsSub?.cancel();
    _ordersSub?.cancel();
    _marketPricesSub?.cancel();
    _searchEventsSub?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _priceFocusNode.dispose();
    _wholesalePriceFocusNode.dispose();
    _quantityFocusNode.dispose();
    _wholesaleMinFocusNode.dispose();
    _deliveryFeeController.dispose();
    _deliveryFeeFocusNode.dispose();
    _priceController.dispose();
    _wholesalePriceController.dispose();
    _wholesaleMinimumController.dispose();
    _quantityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // The Edit button on the selected photo: adjust it (crop/rotate) or
  // swap it for a different one. Delete stays its own button.
  Future<void> _editImage() async {
    final action = await showAgriSheet<String>(
      context: context,
      title: 'Edit photo',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AgriSheetAction(
            icon: Icons.crop_rotate,
            label: 'Crop & rotate',
            onTap: () => Navigator.pop(sheetContext, 'crop'),
          ),
          AgriSheetAction(
            icon: Icons.photo_library_outlined,
            label: 'Replace photo',
            onTap: () => Navigator.pop(sheetContext, 'replace'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'replace') {
      await _pickImage();
    } else {
      await _cropAndRotate();
    }
  }

  // Opens the crop & rotate editor on the current photo and puts the
  // result straight into the Product Photo preview. An already-posted
  // photo (a URL, when editing a listing) is downloaded to a temp file
  // first, since the editor works on local files.
  Future<void> _cropAndRotate() async {
    try {
      String? sourcePath = _file?.path;
      if (sourcePath == null) {
        final url = _imageUrl;
        if (url == null || url.isEmpty) return;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          if (mounted) _showError('Could not load the photo for editing.');
          return;
        }
        final temp = File(
          '${Directory.systemTemp.path}/agritrade_edit_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await temp.writeAsBytes(response.bodyBytes);
        sourcePath = temp.path;
      }

      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        maxWidth: 1000,
        maxHeight: 1000,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop & rotate',
            toolbarColor: _darkGreen,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _darkGreen,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
            ],
          ),
          IOSUiSettings(
            title: 'Crop & rotate',
            rotateButtonsHidden: false,
            aspectRatioLockEnabled: false,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
            ],
          ),
        ],
      );
      if (cropped == null) return; // Farmer backed out — keep the photo.
      final bytes = await cropped.readAsBytes();
      if (!mounted) return;
      setState(() {
        _file = XFile(cropped.path);
        _bytes = bytes;
        _imageUrl = null; // The edited photo is uploaded on Post.
      });
    } catch (error) {
      debugPrint('Photo edit failed: $error');
      if (mounted) _showError('Could not edit the photo. Please try again.');
    }
  }

  Future<void> _pickImage() async {
    final source = await showAgriSheet<ImageSource>(
      context: context,
      title: 'Product photo',
      builder: _imageSourceSheet,
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

  void _removeImage() {
    setState(() {
      _file = null;
      _bytes = null;
      _imageUrl = null;
    });
  }

  Future<bool> _confirmRemoveImage() {
    return showAgriConfirm(
      context: context,
      icon: Icons.delete_outline,
      tone: AgriTone.destructive,
      title: 'Remove product photo?',
      message: 'Are you sure you want to remove this product photo?',
      cancelLabel: 'Keep Photo',
      confirmLabel: 'Remove',
    );
  }

  Widget _productImage({BoxFit fit = BoxFit.cover}) {
    if (_bytes != null) return Image.memory(_bytes!, fit: fit);
    return Image.network(
      _imageUrl!,
      fit: fit,
      errorBuilder: (_, _, _) => Container(
        color: _lightGreenAccent,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: _darkGreen),
      ),
    );
  }

  // Full-screen view of the selected photo; its delete button removes the
  // photo and returns here.
  Future<void> _openImagePreview() async {
    final remove = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (previewContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            title: Text(
              '1 of 1',
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove photo',
                onPressed: () async {
                  final confirmed = await _confirmRemoveImage();
                  if (confirmed && previewContext.mounted) {
                    Navigator.pop(previewContext, true);
                  }
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: _productImage(fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
    if (remove == true && mounted) _removeImage();
  }

  // Content of the "Product photo" source sheet (see _pickImage).
  Widget _imageSourceSheet(BuildContext sheetContext) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AgriSheetAction(
          icon: Icons.photo_camera_outlined,
          label: 'Take a photo',
          onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
        ),
        AgriSheetAction(
          icon: Icons.photo_library_outlined,
          label: 'Choose from gallery',
          onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // The Post/Update button. Every tap ends in visible feedback: a
  // validation message, a price warning dialog, a save error, or the
  // listing being posted — never silence. Anything unexpected thrown along
  // the way is reported instead of being swallowed, and Post is re-enabled.
  Future<void> _save() async {
    // Closes the keyboard so the message isn't hidden behind it.
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _submit();
    } catch (error, stack) {
      debugPrint('Add Product submit failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Something went wrong while posting. Please try again.');
    }
  }

  // The first required/invalid field on the form, in the order the fields
  // sit on screen — or null when everything required is filled in and
  // valid. Drives the Post button's enabled look, the inline red message
  // and the auto-scroll. The AI price comparison is deliberately NOT part
  // of this: a price outside the suggested range never blocks posting.
  _FormIssue? _formIssue() {
    _FormIssue issue(
      String message,
      GlobalKey key, [
      FocusNode? focus,
      bool unsupportedProduct = false,
    ]) => _FormIssue(message, key, focus, unsupportedProduct);

    final name = _nameController.text.trim();
    final quantityText = _quantityController.text.trim();
    final priceText = _priceController.text.trim();
    final unit = _currentUnit;

    if (!_hasImage) {
      return issue('Please add at least one product photo.', _photoKey);
    }

    if (name.isEmpty) {
      return issue('Product name is required.', _nameKey, _nameFocusNode);
    }
    // Product Title must resolve to one of AgriTrade+'s supported
    // commodities (see commodity_master_list.dart) — never a fabricated or
    // unsupported listing. The autocomplete normally fills in an exact
    // supported name; this is the hard gate for anyone who typed past it.
    if (matchSupportedCommodity(name, activeOnly: !_isEditing) == null) {
      return issue(
        'Choose a product from the supported list.',
        _nameKey,
        _nameFocusNode,
        true,
      );
    }
    if (_category == null) {
      return issue(
        'Choose a product from the suggestions to set its category.',
        _nameKey,
        _nameFocusNode,
      );
    }

    if (quantityText.isEmpty) {
      return issue(
        'Available stock is required.',
        _stockKey,
        _quantityFocusNode,
      );
    }
    final quantity = num.tryParse(quantityText);
    if (quantity == null || quantity < 0) {
      return issue(
        'Enter a valid, non-negative stock.',
        _stockKey,
        _quantityFocusNode,
      );
    }
    if (isCountBasedUnit(unit) && quantity != quantity.roundToDouble()) {
      return issue(
        'Stock for $unit must be a whole number.',
        _stockKey,
        _quantityFocusNode,
      );
    }

    if (priceText.isEmpty) {
      return issue('Retail price is required.', _priceKey, _priceFocusNode);
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      return issue('Enter a valid retail price.', _priceKey, _priceFocusNode);
    }

    if (_wholesaleEnabled) {
      final wholesaleText = _wholesalePriceController.text.trim();
      final wholesalePrice = double.tryParse(wholesaleText);
      if (wholesaleText.isEmpty) {
        return issue(
          'Wholesale price is required when wholesale is on.',
          _wholesalePriceKey,
          _wholesalePriceFocusNode,
        );
      }
      if (wholesalePrice == null || wholesalePrice <= 0) {
        return issue(
          'Enter a valid wholesale price.',
          _wholesalePriceKey,
          _wholesalePriceFocusNode,
        );
      }
      if (wholesalePrice >= price) {
        return issue(
          'Wholesale price must be lower than the retail price.',
          _wholesalePriceKey,
          _wholesalePriceFocusNode,
        );
      }

      final minimum = num.tryParse(_wholesaleMinimumController.text.trim());
      if (minimum == null || minimum <= 0) {
        return issue(
          'Enter a valid minimum wholesale quantity.',
          _wholesaleMinKey,
          _wholesaleMinFocusNode,
        );
      }
      if (isCountBasedUnit(unit) && minimum != minimum.roundToDouble()) {
        return issue(
          'Minimum quantity for $unit must be a whole number.',
          _wholesaleMinKey,
          _wholesaleMinFocusNode,
        );
      }
      if (minimum > quantity) {
        return issue(
          'Minimum cannot be greater than the available stock.',
          _wholesaleMinKey,
          _wholesaleMinFocusNode,
        );
      }
    }

    if (_deliveryAvailable) {
      if (_coverageType == null) {
        return issue('Choose where you deliver this product.', _coverageKey);
      }
      if (_coverageType == DeliveryCoverageType.custom &&
          _customAreas.isEmpty) {
        return issue('Select at least one delivery area.', _coverageKey);
      }
      if (_feeType == null) {
        return issue(
          'Choose a fixed delivery fee or "To be arranged with buyer".',
          _deliveryFeeKey,
        );
      }
      if (_feeType == DeliveryFeeType.fixed) {
        final fee = num.tryParse(_deliveryFeeController.text.trim());
        if (fee == null || fee < 0) {
          return issue(
            'Enter the delivery fee amount.',
            _deliveryFeeKey,
            _deliveryFeeFocusNode,
          );
        }
      }
    }
    return null;
  }

  // Order: required fields and field rules (_formIssue, top of the form
  // down) → AI price warnings (advisory) → upload and save.
  Future<void> _submit() async {
    final issue = _formIssue();
    if (issue != null) {
      // From now on every invalid field is highlighted live as the farmer
      // edits, and the first one is brought into view.
      setState(() => _showValidation = true);
      if (issue.unsupportedProduct) {
        _scrollTo(issue.key);
        _showUnsupportedProductDialog();
      } else {
        _showErrorAt(issue.message, issue.key, issue.focus);
      }
      return;
    }

    // Everything below has been validated by _formIssue.
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.parse(_priceController.text.trim());
    final quantity = num.parse(_quantityController.text.trim());
    final unit = _currentUnit;
    final wholesalePrice = _wholesaleEnabled
        ? double.parse(_wholesalePriceController.text.trim())
        : null;
    final wholesaleMinimum = _wholesaleEnabled
        ? num.parse(_wholesaleMinimumController.text.trim())
        : null;

    // Price checks — advisory only, never a block (see the PRICE WARNINGS
    // section). Retail is checked against the retail range, wholesale
    // against the wholesale range. "Post Anyway" always lets the listing
    // through; far-above-range prices also save an internal flag for the
    // Admin Moderation Queue.
    //
    // The ONLY early return in here is the farmer tapping "Adjust Price"
    // (or dismissing the dialog). Anything going wrong inside the
    // comparison itself is swallowed and posting carries on unflagged.
    _checkPrice(wholesale: false);
    if (_wholesaleEnabled) _checkPrice(wholesale: true);
    final flaggedPrices = <Map<String, dynamic>>[];
    for (final wholesale in [false, if (_wholesaleEnabled) true]) {
      final entered = wholesale ? wholesalePrice! : price;
      PriceDeviation? deviation;
      try {
        deviation = _deviationFor(entered, wholesale: wholesale);
      } catch (_) {
        deviation = null;
      }
      if (deviation == null) continue;

      final confirmed = wholesale ? _confirmedWholesale : _confirmedRetail;
      final alreadyConfirmed =
          confirmed != null &&
          deviation.coveredBy(confirmed.price, confirmed.level);
      if (deviation.needsConfirmation && !alreadyConfirmed) {
        final postAnyway = await _confirmPriceDeviation(
          deviation,
          wholesale: wholesale,
        );
        if (!mounted) return;
        if (!postAnyway) {
          // "Adjust Price": take the farmer straight to that price field.
          _scrollTo(wholesale ? _wholesalePriceKey : _priceKey);
          (wholesale ? _wholesalePriceFocusNode : _priceFocusNode)
              .requestFocus();
          return;
        }
        final answer = (price: entered, level: deviation.level);
        if (wholesale) {
          _confirmedWholesale = answer;
        } else {
          _confirmedRetail = answer;
        }
      }

      if (deviation.shouldFlag) {
        flaggedPrices.add({
          'pricingType': wholesale ? 'wholesale' : 'retail',
          'enteredPrice': entered,
          'suggestedLowerPrice': deviation.lower,
          'suggestedUpperPrice': deviation.upper,
          'percentAbove': double.parse(deviation.percentLabel),
          'dataAvailability': deviation.dataAvailability,
        });
      }
    }
    final Map<String, dynamic>? priceFlag = flaggedPrices.isEmpty
        ? null
        : {
            'type': 'high_price',
            'label': PriceDeviationConfig.highPriceFlagLabel,
            'reason': PriceDeviationConfig.highPriceFlagReason,
            'reviewStatus': PriceDeviationConfig.highPriceFlagStatus,
            'productName': name,
            'unit': unit,
            'items': flaggedPrices,
          };

    setState(() => _loading = true);

    String? error;
    try {
      // Build the final image URL list (upload the new pick first, if any).
      final List<String> imageUrls = [];
      if (_file != null) {
        final url = await _cloudinaryService.uploadImage(_file!);
        if (url == null) {
          if (!mounted) return;
          _showError('Image upload failed. Check your internet and try again.');
          return;
        }
        imageUrls.add(url);
      } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
        imageUrls.add(_imageUrl!);
      }

      final hadPriceFlag = widget.existingData?['priceFlag'] != null;
      // Only written when it actually changed, so an edit that doesn't
      // involve the harvest date never touches the field.
      final harvestDate = categoryHasHarvestDate(_category)
          ? _harvestDate
          : null;
      final storedHarvest = widget.existingData?['harvestDate'];
      final harvestChanged = storedHarvest is Timestamp
          ? harvestDate == null ||
                !DateUtils.isSameDay(storedHarvest.toDate(), harvestDate)
          : harvestDate != null;
      Future<String?> saveProduct(Map<String, dynamic>? flag) {
        if (_isEditing) {
          return _productService.updateProduct(
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
            deliveryCoverage: _deliveryCoverage?.toMap(),
            commodity: _selectedCommodity,
            unit: unit,
            priceFlag: flag,
            clearPriceFlag: flag == null && hadPriceFlag,
            harvestDate: harvestChanged ? harvestDate : null,
            clearHarvestDate: harvestChanged && harvestDate == null,
          );
        }
        return _productService.addProduct(
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
          deliveryCoverage: _deliveryCoverage?.toMap(),
          commodity: _selectedCommodity,
          unit: unit,
          priceFlag: flag,
          harvestDate: harvestDate,
        );
      }

      error = await saveProduct(priceFlag);
      // The moderation flag must never be the reason a listing fails to
      // save (e.g. rules that don't allow the field yet) — if the flagged
      // save is rejected, post the listing itself without the flag.
      if (error != null && priceFlag != null) {
        error = await saveProduct(null);
      }
    } catch (_) {
      error = 'Could not save product. Please try again.';
    } finally {
      // Whatever happened, Post goes back to its normal enabled state.
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    if (error == null) {
      _showMessage(_isEditing ? 'Product updated!' : 'Product posted!');
      _closeScreen();
    } else {
      _showError(error);
    }
  }

  // ==========================================================
  // PRICE WARNINGS — compares the farmer's Retail Price with the retail
  // suggested range and the Wholesale Price with the wholesale suggested
  // range (never mixed). Reads each recommendation as-is (see
  // _computeRecommendation, which already only pools same-unit data); it
  // never changes how a recommendation is worked out. Thresholds live in
  // PriceDeviationConfig (price_deviation.dart). Advisory only — nothing
  // here blocks, hides or penalises a listing.
  // ==========================================================

  PriceRecommendation? _recoFor({required bool wholesale}) {
    final commodity = _matchedCommodity;
    if (commodity == null) return null;
    return _computeRecommendation(
      commodity,
      pricingType: wholesale ? 'wholesale' : 'retail',
    );
  }

  // Null when the price is inside the range, or there is no reliable range
  // to compare against.
  PriceDeviation? _deviationFor(double price, {required bool wholesale}) {
    final reco = _recoFor(wholesale: wholesale);
    if (reco == null ||
        reco.tier == PriceDataTier.insufficient ||
        reco.suggestedLow == null ||
        reco.suggestedHigh == null) {
      return null;
    }
    return PriceDeviation.evaluate(
      price: price,
      lower: reco.suggestedLow!,
      upper: reco.suggestedHigh!,
      dataAvailability: reco.tier.dataAvailabilityLabel,
      limitedData: reco.tier == PriceDataTier.referenceOnly,
    );
  }

  String _peso(double value) =>
      '₱${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2)}';

  // Limited-data warnings stay amber whatever the percentage — the range
  // itself is less certain, so the warning is softer.
  Color _deviationColor(PriceDeviation deviation) {
    if (deviation.limitedData) return Colors.amber.shade800;
    return switch (deviation.level) {
      PriceDeviationLevel.strong => Colors.red.shade700,
      PriceDeviationLevel.confirm => Colors.orange.shade800,
      PriceDeviationLevel.mild => Colors.amber.shade800,
    };
  }

  String _deviationNote(PriceDeviation deviation) {
    final String note;
    if (deviation.level == PriceDeviationLevel.mild) {
      note = 'Slightly ${deviation.directionLabel} the suggested range.';
    } else if (deviation.isAbove) {
      note = 'Higher pricing may reduce buyer interest.';
    } else {
      note =
          'Your product may be underpriced compared with the suggested market range.';
    }
    return deviation.limitedData
        ? '$note This recommendation is based on limited data.'
        : note;
  }

  // Marks the typed price as "checked" so its note appears. Called when a
  // price field loses focus and on Post — never per keystroke, so the
  // warning doesn't flicker while the farmer is still typing.
  void _checkPrice({required bool wholesale}) {
    final price = double.tryParse(
      (wholesale ? _wholesalePriceController : _priceController).text.trim(),
    );
    if (!mounted) return;
    setState(() {
      if (wholesale) {
        _checkedWholesalePrice = price;
      } else {
        _checkedRetailPrice = price;
      }
    });
  }

  // The short note under a price field. Shown only for the last checked
  // price; it disappears as soon as the farmer edits the field again and
  // is re-evaluated the next time the field is left.
  Widget _priceWarningBanner({required bool wholesale}) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: wholesale ? _wholesalePriceController : _priceController,
      builder: (context, value, _) {
        final price = double.tryParse(value.text.trim());
        final checked = wholesale
            ? _checkedWholesalePrice
            : _checkedRetailPrice;
        if (price == null || price <= 0 || price != checked) {
          return const SizedBox.shrink();
        }

        final reco = _recoFor(wholesale: wholesale);
        if (reco == null) return const SizedBox.shrink();
        if (reco.tier == PriceDataTier.insufficient) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, left: 6),
            child: Text(
              'Insufficient data for price comparison.',
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                color: Colors.grey[600],
              ),
            ),
          );
        }

        final deviation = _deviationFor(price, wholesale: wholesale);
        if (deviation == null) return const SizedBox.shrink();
        final color = _deviationColor(deviation);
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your price is ${deviation.percentLabel}% ${deviation.directionLabel} '
                  'the suggested range. ${_deviationNote(deviation)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ),
              IconButton(
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.error_outline, size: 18, color: color),
                tooltip: 'Why am I seeing this?',
                onPressed: () => _showPriceCalculation(deviation),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _deviationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: Colors.black54,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // "Why am I seeing this?" — the calculation, spelled out.
  void _showPriceCalculation(PriceDeviation deviation) {
    final unit = _currentUnit;
    final entered = _peso(deviation.enteredPrice);
    final compared = _peso(deviation.comparisonPrice);
    final formula = deviation.isAbove
        ? '($entered - $compared) ÷ $compared × 100'
        : '($compared - $entered) ÷ $compared × 100';

    showAgriDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: AgriFrostedCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: _lightGreenAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        color: _darkGreen,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Why am I seeing this?',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your price is compared with the ${deviation.isAbove ? 'upper' : 'lower'} '
                  'end of the AI suggested range.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _deviationRow('Entered price', '$entered/$unit'),
                _deviationRow(
                  deviation.isAbove
                      ? 'Suggested upper range'
                      : 'Suggested lower range',
                  '$compared/$unit',
                ),
                _deviationRow('Data availability', deviation.dataAvailability),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _lightGreenAccent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${deviation.percentLabel}% ${deviation.directionLabel} suggested range',
                        style: GoogleFonts.montserrat(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _darkGreen,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$formula = ${deviation.percentLabel}%',
                        style: GoogleFonts.montserrat(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  deviation.limitedData
                      ? 'This recommendation is based on limited data. The AI suggestion is advisory. '
                            'You still make the final pricing decision.'
                      : 'The AI suggestion is advisory. You still make the final pricing decision.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    color: Colors.black45,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _darkGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Got it',
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Confirmation shown on Post for a price that needs one (see
  // PriceDeviation.needsConfirmation). Returns true only for "Post Anyway".
  Future<bool> _confirmPriceDeviation(
    PriceDeviation deviation, {
    required bool wholesale,
  }) async {
    // Orange is reserved for the warning icon and the percentage box; dark
    // green for the title, buttons and link; the card itself stays neutral.
    final color = Colors.orange.shade800;
    final unit = _currentUnit;
    final kind = wholesale ? 'wholesale' : 'retail';
    // Neutral, "may"-worded consequences — possibilities, not predictions.
    // Kept as separate short paragraphs rather than one dense block.
    final explanation = deviation.isAbove
        ? 'Proceeding with this price may reduce buyer interest and make your listing '
              'less competitive compared with similar products.'
        : 'Your product may be underpriced compared with the suggested market range.';
    final notes = [
      if (deviation.limitedData)
        'This recommendation is based on limited data.',
      if (deviation.shouldFlag)
        'Because this price exceeds the moderation threshold, the listing may also be '
            'sent to the Admin Moderation Queue for review.',
    ];

    final postAnyway = await showAgriDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: AgriFrostedCard(
          child: _priceWarningContent(
            dialogContext,
            deviation: deviation,
            color: color,
            unit: unit,
            kind: kind,
            explanation: explanation,
            notes: notes,
          ),
        ),
      ),
    );
    return postAnyway == true;
  }

  Widget _priceWarningContent(
    BuildContext dialogContext, {
    required PriceDeviation deviation,
    required Color color,
    required String unit,
    required String kind,
    required String explanation,
    required List<String> notes,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: color, size: 24),
          ),
          const SizedBox(height: 14),
          Text(
            deviation.isAbove ? 'High Price Warning' : 'Low Price Warning',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 8),
          // The headline figure — highlighted so it reads first.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text.rich(
              TextSpan(
                text: 'Your $kind price is ',
                children: [
                  TextSpan(
                    text:
                        '${deviation.percentLabel}% ${deviation.directionLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' the suggested range.'),
                ],
              ),
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Price details as short aligned rows.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _deviationRow(
                  'Entered price',
                  '${_peso(deviation.enteredPrice)}/$unit',
                ),
                _deviationRow(
                  deviation.isAbove
                      ? 'Suggested upper range'
                      : 'Suggested lower range',
                  '${_peso(deviation.comparisonPrice)}/$unit',
                ),
                _deviationRow(
                  'Suggested range',
                  '${_peso(deviation.lower)} – ${_peso(deviation.upper)}/$unit',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              color: Colors.black87,
              height: 1.45,
            ),
          ),
          for (final note in notes) ...[
            const SizedBox(height: 8),
            Text(
              note,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                color: Colors.black54,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    'Adjust Price',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _darkGreen,
                    side: const BorderSide(color: _darkGreen, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    'Post Anyway',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _showPriceCalculation(deviation),
            child: Text(
              'Why am I seeing this?',
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _darkGreen,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final confirm = await showAgriConfirm(
      context: context,
      icon: Icons.delete_outline,
      tone: AgriTone.destructive,
      title: 'Delete Product?',
      message: 'This will permanently remove this product.',
      confirmLabel: 'Delete',
    );
    if (!confirm) return;
    setState(() => _loading = true);
    final error = await _productService.deleteProduct(widget.productId!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      _showMessage('Product deleted.');
      _closeScreen();
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
      _showMessage(
        _isArchived
            ? 'Listing archived — hidden from the marketplace until you restore it.'
            : 'Listing restored — visible in the marketplace again.',
      );
    } else {
      _showMessage(error);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    // Replace whatever is showing rather than queueing behind it — a
    // queued message only appears seconds later, which reads as the tap
    // having done nothing.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isError ? Colors.red.shade700 : _darkGreen,
          content: Row(
            children: [
              if (isError) ...[
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.montserrat(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // Validation failures and save errors — red, so they can't be mistaken
  // for a success message.
  void _showError(String message) => _showMessage(message, isError: true);

  // Brings the part of the form a validation error is about into view.
  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  // Shows a validation error, scrolls to the field it is about and, for a
  // text field, puts the cursor in it.
  //
  // The message is also pinned in red right under that field (see
  // _fieldError), so the farmer still sees what is wrong even if the
  // snackbar at the bottom is missed or covered — e.g. by the keyboard or
  // a system toast.
  void _showErrorAt(String message, GlobalKey key, [FocusNode? focusNode]) {
    setState(() => _showValidation = true);
    _showError(message);
    // After the frame, so the inline message is laid out before scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollTo(key);
      focusNode?.requestFocus();
    });
  }

  bool _hasIssue(GlobalKey key) => _shownIssue?.key == key;

  // The inline validation message for the section identified by [key] —
  // shown while it is the first invalid field, gone as soon as it's fixed.
  Widget _fieldError(GlobalKey key) {
    final issue = _shownIssue;
    if (issue == null || issue.key != key) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              issue.message,
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (_loading || _confirmingExit || _allowPop) return;
    _confirmingExit = true;
    final shouldLeave = await showAgriConfirm(
      context: context,
      icon: Icons.logout,
      title: 'Leave product posting?',
      message: 'Your changes will not be saved if you leave.',
      cancelLabel: 'Stay',
      confirmLabel: 'Leave',
    );
    _confirmingExit = false;
    if (!mounted || shouldLeave != true) return;
    _closeScreen();
  }

  void _closeScreen() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
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
    await showAgriDialog<void>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.info_outline,
        tone: AgriTone.warning,
        title: const Text('Product not currently supported'),
        content: const Text(
          'AgriTrade+ currently supports selected commodities based on the system '
          'scope and available agricultural data. Please choose a product from the '
          'Supported Products list.',
        ),
        actions: [
          AgriDialogButton(
            label: 'OK',
            onPressed: () => Navigator.pop(dialogContext),
          ),
          AgriDialogButton(
            label: 'View Products',
            kind: AgriButtonKind.primary,
            onPressed: () {
              Navigator.pop(dialogContext);
              _openSupportedProducts();
            },
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
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Colors.amber.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not all goods are available to sell. AgriTrade+ currently supports '
                  'selected commodities only — choose a product from the supported list.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.black87,
                    height: 1.35,
                  ),
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

  InputDecoration _inputDecoration(
    String hint, {
    IconData? icon,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.montserrat(color: Colors.black38, fontSize: 13.5),
      prefixIcon: icon != null ? Icon(icon, color: _darkGreen) : null,
      prefix: prefix,
      // Centered so a text suffix (the unit) lines up with the typed value
      // instead of sitting in the field's top corner.
      suffixIcon: suffix == null ? null : Center(widthFactor: 1, child: suffix),
      // Borderless — the white pill, lift shadow and focus glow all come
      // from the _GlowPlate wrapped around each field (same look as the
      // registration form's GlowField).
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }

  Widget _label(String text, {Key? key}) {
    return Padding(
      key: key,
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

  Future<void> _pickHarvestDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate ?? now,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      // A harvest can't be in the future.
      lastDate: now,
      helpText: 'Harvest date',
    );
    if (picked != null && mounted) setState(() => _harvestDate = picked);
  }

  // When this batch was harvested. Optional. Updating it (with the stock,
  // and the photo or price if they changed) is how a farmer refreshes this
  // same listing for a new batch instead of posting the product again.
  Widget _harvestDateField() {
    final date = _harvestDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Harvest Date'),
        _GlowPlate(
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _pickHarvestDate,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined, size: 18, color: _darkGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      date == null
                          ? 'Select harvest date'
                          : DateFormat('MMM d, y').format(date),
                      style: GoogleFonts.montserrat(
                        fontSize: date == null ? 13.5 : 14,
                        color: date == null ? Colors.black38 : Colors.black87,
                      ),
                    ),
                  ),
                  if (date != null)
                    IconButton(
                      tooltip: 'Clear harvest date',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _harvestDate = null),
                    )
                  else
                    const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(
            _isEditing
                ? 'New batch? Update the harvest date and stock here — no '
                      'need to post the product again.'
                : 'Buyers see this as "Harvested today", "Harvested 2 days '
                      'ago" and so on.',
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: Colors.grey[600],
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  // ---- Delivery coverage + fee (shown while Delivery Available is on) ----
  Widget _deliverySetup() {
    final nearby = nearbyAreasFor(_farmOrigin).map((a) => a.name).toList();
    final town = _farmOrigin.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCEDC8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Delivery Coverage', key: _coverageKey),
          _choiceTile(
            selected: _coverageType == DeliveryCoverageType.sameBarangay,
            title: DeliveryCoverageType.sameBarangay.label,
            subtitle: _farmBarangay.isEmpty
                ? 'Only buyers in your barangay'
                : 'Only buyers in Barangay $_farmBarangay',
            error: _hasIssue(_coverageKey),
            onTap: () => setState(
              () => _coverageType = DeliveryCoverageType.sameBarangay,
            ),
          ),
          _choiceTile(
            selected: _coverageType == DeliveryCoverageType.municipality,
            title: DeliveryCoverageType.municipality.label,
            subtitle: 'Anywhere in $town',
            error: _hasIssue(_coverageKey),
            onTap: () => setState(
              () => _coverageType = DeliveryCoverageType.municipality,
            ),
          ),
          _choiceTile(
            selected: _coverageType == DeliveryCoverageType.nearby,
            title: DeliveryCoverageType.nearby.label,
            subtitle: nearby.isEmpty
                ? '$town and the towns around it'
                : '$town, ${nearby.join(', ')}',
            error: _hasIssue(_coverageKey),
            onTap: () =>
                setState(() => _coverageType = DeliveryCoverageType.nearby),
          ),
          _choiceTile(
            selected: _coverageType == DeliveryCoverageType.custom,
            title: DeliveryCoverageType.custom.label,
            subtitle: 'Choose specific municipalities/cities',
            error: _hasIssue(_coverageKey),
            onTap: () {
              setState(() {
                _coverageType = DeliveryCoverageType.custom;
                // Start from the farm's own town — usually wanted.
                if (_customAreas.isEmpty) _customAreas = [_farmOrigin];
              });
            },
          ),
          if (_coverageType == DeliveryCoverageType.custom) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final area in _customAreas)
                  InputChip(
                    label: Text(
                      area.name,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _darkGreen,
                      ),
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFDCEDC8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    deleteIconColor: _darkGreen,
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(
                      () => _customAreas = [..._customAreas]..remove(area),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16, color: _darkGreen),
                  label: Text(
                    _customAreas.isEmpty ? 'Select areas' : 'Add or remove',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _darkGreen,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _darkGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final picked = await showDeliveryAreaPicker(
                      context,
                      initial: _customAreas,
                    );
                    if (picked != null && mounted) {
                      setState(() => _customAreas = picked);
                    }
                  },
                ),
              ],
            ),
          ],
          _fieldError(_coverageKey),
          const SizedBox(height: 12),
          _label('Delivery Fee', key: _deliveryFeeKey),
          Row(
            children: [
              Expanded(
                child: _choiceTile(
                  selected: _feeType == DeliveryFeeType.fixed,
                  title: 'Fixed fee',
                  error: _hasIssue(_deliveryFeeKey) && _feeType == null,
                  onTap: () {
                    setState(() => _feeType = DeliveryFeeType.fixed);
                    _deliveryFeeFocusNode.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _choiceTile(
                  selected: _feeType == DeliveryFeeType.arranged,
                  title: 'To be arranged',
                  error: _hasIssue(_deliveryFeeKey) && _feeType == null,
                  onTap: () =>
                      setState(() => _feeType = DeliveryFeeType.arranged),
                ),
              ),
            ],
          ),
          if (_feeType == DeliveryFeeType.fixed)
            _GlowPlate(
              error: _hasIssue(_deliveryFeeKey),
              child: TextField(
                controller: _deliveryFeeController,
                focusNode: _deliveryFeeFocusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: GoogleFonts.montserrat(fontSize: 14),
                decoration: _inputDecoration(
                  'e.g., 50',
                  prefix: Text(
                    '₱ ',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _darkGreen,
                    ),
                  ),
                ),
              ),
            )
          else if (_feeType == DeliveryFeeType.arranged)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Text(
                'Delivery fee: To be arranged with buyer',
                style: GoogleFonts.montserrat(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          _fieldError(_deliveryFeeKey),
          const SizedBox(height: 10),
          Text(
            'Buyers outside this area can still message you to ask about '
            'long-distance delivery.',
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: Colors.grey[600],
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceTile({
    required bool selected,
    required String title,
    String? subtitle,
    bool error = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _darkGreen
                  : error
                  ? Colors.red.shade400
                  : const Color(0xFFE0E6DC),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 19,
                color: selected ? _darkGreen : Colors.grey[500],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Profile header ----
  Widget _profileHeader() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final savedName = (data?['name'] ?? data?['fullName'])
            ?.toString()
            .trim();
        final name = savedName != null && savedName.isNotEmpty
            ? savedName
            : (user?.displayName ?? 'Farmer');
        final savedPhoto = data?['photoUrl']?.toString().trim();
        final photoUrl = savedPhoto != null && savedPhoto.isNotEmpty
            ? savedPhoto
            : user?.photoURL;
        return Row(
          children: [
            ProfileAvatar(photoUrl: photoUrl, name: name, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
            ),
          ],
        );
      },
    );
  }

  // ---- Single, compact photo slot ----
  Widget _imageSlot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                'Product Photo',
                style: GoogleFonts.montserrat(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'High-quality photos sell faster',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: _hasImage ? _imageSelected() : _imageEmpty(),
        ),
      ],
    );
  }

  Widget _imageEmpty() {
    return Material(
      color: _lightGreenAccent.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _loading ? null : _pickImage,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            // Red outline while the "photo required" error is showing.
            color: _hasIssue(_photoKey)
                ? Colors.red.shade700
                : _darkGreen.withValues(alpha: 0.45),
            radius: 14,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 28,
                  color: _darkGreen,
                ),
                const SizedBox(height: 6),
                Text(
                  'Add product photo',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    color: _darkGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to take a photo or choose from gallery',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageSelected() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lightGreenAccent, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openImagePreview,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _productImage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product photo',
                          style: GoogleFonts.montserrat(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to preview, change or remove',
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _imageAction(
                icon: Icons.edit_outlined,
                tooltip: 'Edit photo',
                onPressed: _editImage,
              ),
              const SizedBox(height: 6),
              _imageAction(
                icon: Icons.delete_outline,
                tooltip: 'Remove photo',
                onPressed: () async {
                  if (await _confirmRemoveImage()) _removeImage();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    // A plain 32px InkWell circle rather than an IconButton, whose minimum
    // tap target would pad it back out to 48px.
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _lightGreenAccent.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _loading ? null : onPressed,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: _darkGreen, size: 17),
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
          style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 12.5),
        ),
      );
    }

    if (commodity == null) {
      return _recoShell(
        child: Text(
          'AI-assisted price recommendations are only available for AgriTrade+\'s supported '
          'commodities (see Supported Products above) — "$typedName" isn\'t recognized as one yet.',
          style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 12.5),
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
              style: GoogleFonts.montserrat(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Not enough pricing data is available for this commodity yet. Please check again after '
              'the latest reference price has been provided or more marketplace data becomes available.',
              style: GoogleFonts.montserrat(
                color: Colors.black54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can still set your own selling price below.',
              style: GoogleFonts.montserrat(
                color: Colors.black45,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
              ),
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

    // Everything explanatory lives in the info sheet behind the card's "!"
    // icon (see _showRecoInfo) so the card stays short; the numbers and the
    // action stay visible.
    final details = <Widget>[
      if (result.referenceEffectiveDate != null) ...[
        Text(
          'Reference price last updated: ${DateFormat('MMM d, y').format(result.referenceEffectiveDate!)}'
          '${result.referenceIsStale ? ' (may be outdated)' : ''}',
          style: GoogleFonts.montserrat(color: Colors.black45, fontSize: 10.5),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        isColdStart
            ? 'This recommendation is currently based mainly on the latest reference commodity price. '
                  'Future recommendations will improve as AgriTrade+ collects more actual marketplace activity.'
            : 'Based on the latest reference price, recent completed transactions, active listings, and '
                  'current AgriTrade+ marketplace activity.',
        style: GoogleFonts.montserrat(
          color: Colors.black54,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Based on:',
        style: GoogleFonts.montserrat(
          color: Colors.black87,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      if (result.referencePrice != null)
        _basisLine(
          result.referenceIsStale
              ? 'Latest reference commodity price (last updated a while ago)'
              : 'Latest reference commodity price',
        ),
      if (result.transactionCount > 0)
        _basisLine(
          '${result.transactionCount} recent completed transaction(s)',
        ),
      if (result.listingCount > 0)
        _basisLine('${result.listingCount} active listing(s)'),
      if (result.usedSupplyDemand)
        _basisLine('Current supply and buyer demand'),
      if (isColdStart)
        _basisLine(
          'AgriTrade+ does not yet have enough marketplace transaction data for this product.',
        )
      else
        _basisLine(
          'Weighted toward actual completed sales over asking prices, and outlier-resistant.',
        ),
      if (result.tier == PriceDataTier.limited)
        _basisLine(
          'Limited data so far — treat this as a rough starting point, not a confident market read.',
        ),
      const SizedBox(height: 6),
      Text(
        'This is an AI-assisted suggestion only — you always make the final pricing decision.',
        style: GoogleFonts.montserrat(
          color: Colors.black45,
          fontSize: 10.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    ];

    return _recoShell(
      details: details,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _lightGreenAccent.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested Price',
                  style: GoogleFonts.montserrat(
                    color: Colors.black54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: '₱${suggested.toStringAsFixed(2)}',
                    children: [
                      TextSpan(
                        text: ' / $_currentUnit',
                        style: GoogleFonts.montserrat(
                          color: Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  style: GoogleFonts.montserrat(
                    color: _darkGreen,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _secondaryStat(
            'Suggested range',
            '₱${result.suggestedLow!.toStringAsFixed(2)} – ₱${result.suggestedHigh!.toStringAsFixed(2)}',
          ),
          _secondaryStat(
            'Reference price',
            result.referencePrice != null
                ? '₱${result.referencePrice!.toStringAsFixed(2)} / $_currentUnit'
                : 'Not set',
          ),
          _secondaryStat(
            'Marketplace range',
            result.marketplaceLow != null
                ? '₱${result.marketplaceLow!.toStringAsFixed(2)} – ₱${result.marketplaceHigh!.toStringAsFixed(2)}'
                : 'No active listings yet',
          ),
          _secondaryStat(
            'Data availability',
            result.tier.dataAvailabilityLabel,
          ),
          if (_wholesaleEnabled) ...[
            const SizedBox(height: 8),
            Divider(color: _darkGreen.withValues(alpha: 0.15)),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final wholesaleResult = _computeRecommendation(
                  commodity,
                  pricingType: 'wholesale',
                );
                if (wholesaleResult.tier == PriceDataTier.insufficient) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHOLESALE PRICE RECOMMENDATION',
                        style: GoogleFonts.montserrat(
                          color: Colors.black87,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Wholesale price recommendation currently unavailable due to limited wholesale market data.',
                        style: GoogleFonts.montserrat(
                          color: Colors.black54,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You can set the wholesale price manually. AgriTrade+ will not create a discount or wholesale reference price automatically.',
                        style: GoogleFonts.montserrat(
                          color: Colors.black45,
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
                        color: Colors.black54,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${wholesaleSuggested.toStringAsFixed(2)} / $_currentUnit',
                      style: GoogleFonts.montserrat(
                        color: _darkGreen,
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
                        color: Colors.black45,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        _wholesalePriceController.text = wholesaleSuggested
                            .toStringAsFixed(2);
                        _showMessage(
                          'Wholesale suggested price applied — you can still edit it.',
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _darkGreen,
                        side: const BorderSide(color: _darkGreen),
                      ),
                      child: Text(
                        'Use Wholesale Suggested Price',
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _priceController.text = suggested.toStringAsFixed(2);
                _showMessage(
                  'Suggested price applied — you can still edit it.',
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Use Suggested Price',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The "!" sheet: how the recommendation is worked out. [details] is the
  // live, result-specific explanation when a recommendation exists; without
  // one (nothing typed yet, unsupported product, no data) it falls back to
  // the general description.
  void _showRecoInfo(List<Widget>? details) {
    showAgriSheet<void>(
      context: context,
      isScrollControlled: true,
      title: 'About this price recommendation',
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...(details ??
                [
                  Text(
                    'The suggested price is worked out from the latest reference commodity price and '
                    'current AgriTrade+ marketplace activity, whenever that data is available.',
                    style: GoogleFonts.montserrat(
                      color: Colors.black54,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Based on:',
                    style: GoogleFonts.montserrat(
                      color: Colors.black87,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _basisLine('Latest reference commodity price'),
                  _basisLine('Recent completed transactions'),
                  _basisLine('Active listings'),
                  _basisLine('Current supply and buyer demand'),
                  _basisLine(
                    'Weighted toward actual completed sales over asking prices, and outlier-resistant.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This is an AI-assisted suggestion only — you always make the final pricing decision.',
                    style: GoogleFonts.montserrat(
                      color: Colors.black45,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ]),
          ],
        ),
      ),
    );
  }

  Widget _secondaryStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.montserrat(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.montserrat(
                color: Colors.black87,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recoShell({required Widget child, List<Widget>? details}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _darkGreen.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: _lightGreenAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: _darkGreen,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AI-Assisted Price Recommendation',
                  style: GoogleFonts.montserrat(
                    color: Colors.black87,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
              ),
              IconButton(
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.error_outline,
                  color: _darkGreen,
                  size: 20,
                ),
                tooltip: 'About this recommendation',
                onPressed: () => _showRecoInfo(details),
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
            child: Icon(Icons.check_circle, color: _darkGreen, size: 13),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                color: Colors.black54,
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
    // Re-evaluated every build so the Post button and the red highlights
    // always reflect what is on the form right now.
    _issue = _formIssue();
    final formComplete = _issue == null;

    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: _lightGreenBg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _confirmExit,
          ),
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
                icon: Icon(
                  _isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
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
                      Icon(
                        Icons.archive_outlined,
                        size: 18,
                        color: Colors.orange[800],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This listing is archived and hidden from the marketplace.',
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE8ECE6)),
              const SizedBox(height: 14),

              // ---- Single photo slot ----
              KeyedSubtree(key: _photoKey, child: _imageSlot()),
              _fieldError(_photoKey),
              const SizedBox(height: 14),

              _label('Product Name', key: _nameKey),
              Autocomplete<String>(
                textEditingController: _nameController,
                focusNode: _nameFocusNode,
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  final names = CommodityRegistry.instance.activeNames;
                  if (query.isEmpty) return names;
                  return names.where((c) => c.toLowerCase().contains(query));
                },
                onSelected: (selection) => setState(() {
                  _selectedCommodity = selection;
                  _category = categoryOfCommodity(selection);
                }),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) {
                      return _GlowPlate(
                        error: _hasIssue(_nameKey),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: GoogleFonts.montserrat(fontSize: 14),
                          decoration: _inputDecoration('e.g., Eggplant'),
                        ),
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(14),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 220,
                          maxWidth: 340,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(
                                option,
                                style: GoogleFonts.montserrat(fontSize: 13.5),
                              ),
                              subtitle: Text(
                                categoryOfCommodity(option) ?? '',
                                style: GoogleFonts.montserrat(
                                  fontSize: 10.5,
                                  color: Colors.grey[600],
                                ),
                              ),
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
                'Start typing to select a supported product.',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              _fieldError(_nameKey),
              const SizedBox(height: 8),
              _supportedProductsBanner(),
              const SizedBox(height: 12),

              // ---- Category + Quantity side by side ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Category'),
                        _GlowPlate(
                          child: InputDecorator(
                            decoration: _inputDecoration(''),
                            child: Text(
                              _category ?? 'Select a product name first',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                color: _category == null
                                    ? Colors.black38
                                    : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Available Stock', key: _stockKey),
                        _GlowPlate(
                          error: _hasIssue(_stockKey),
                          child: TextField(
                            controller: _quantityController,
                            focusNode: _quantityFocusNode,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: !_isCountBasedUnit,
                            ),
                            // Numbers only — the unit is the read-only
                            // suffix below, set by the selected product.
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(
                                  _isCountBasedUnit ? r'[0-9]' : r'[0-9.]',
                                ),
                              ),
                            ],
                            style: GoogleFonts.montserrat(fontSize: 14),
                            decoration: _inputDecoration(
                              '0',
                              suffix: Padding(
                                padding: const EdgeInsets.only(right: 18),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    _currentUnit,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _darkGreen,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _fieldError(_stockKey),
              const SizedBox(height: 18),

              // ---- Harvest date (produce only) ----
              if (categoryHasHarvestDate(_category)) ...[
                _harvestDateField(),
                const SizedBox(height: 18),
              ],

              // ---- AI price recommendation (by product name) ----
              _priceRecommendation(),
              const SizedBox(height: 18),

              // ---- Retail Price ----
              _label('Retail Price', key: _priceKey),
              _GlowPlate(
                error: _hasIssue(_priceKey),
                child: TextField(
                  controller: _priceController,
                  focusNode: _priceFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                        '/ $_currentUnit',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _fieldError(_priceKey),
              _priceWarningBanner(wholesale: false),
              const SizedBox(height: 12),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Offer Wholesale',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Set a lower bulk price once the buyer reaches your minimum quantity.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
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
                _label('Wholesale Price', key: _wholesalePriceKey),
                _GlowPlate(
                  error: _hasIssue(_wholesalePriceKey),
                  child: TextField(
                    controller: _wholesalePriceController,
                    focusNode: _wholesalePriceFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                          '/ $_currentUnit',
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _fieldError(_wholesalePriceKey),
                _priceWarningBanner(wholesale: true),
                const SizedBox(height: 12),
                _label('Minimum Wholesale Quantity', key: _wholesaleMinKey),
                _GlowPlate(
                  error: _hasIssue(_wholesaleMinKey),
                  child: TextField(
                    controller: _wholesaleMinimumController,
                    focusNode: _wholesaleMinFocusNode,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !_isCountBasedUnit,
                    ),
                    style: GoogleFonts.montserrat(fontSize: 14),
                    decoration: _inputDecoration(
                      'e.g., 20',
                      suffix: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          _currentUnit,
                          style: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _fieldError(_wholesaleMinKey),
                const SizedBox(height: 12),
              ],

              // ---- Description ----
              _label('Description'),
              // Multi-line, so a softer corner than the single-line pills.
              _GlowPlate(
                radius: 22,
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: GoogleFonts.montserrat(fontSize: 14),
                  decoration: _inputDecoration(
                    'Tell buyers about how it was raised or grown...',
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ---- Fulfillment ----
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
              if (_deliveryAvailable) _deliverySetup(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Pick-up Available',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Buyers can collect the order from you.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
                ),
                activeThumbColor: _darkGreen,
                value: _pickupOnly,
                onChanged: (v) => setState(() => _pickupOnly = v),
              ),
              const SizedBox(height: 16),

              // ---- Post ----
              // Greyed out (disabled look) until every required field is
              // valid. It still responds to a tap, though: instead of
              // posting, that tap highlights the first missing/invalid field
              // and scrolls to it — a fully dead button would leave the
              // farmer hunting through the long form for what's missing.
              // A price outside the AI range never greys it out.
              if (!formComplete && !_loading) ...[
                Text(
                  'Complete the required fields to post.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: formComplete
                      ? _darkGreen
                      : Colors.grey.shade400,
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
      ),
    );
  }
}

/// The registration form's field plate (see GlowField) for this screen's
/// inputs: a white pill with a faint lift shadow, plus the brand-green glow
/// while the field inside it has focus.
class _GlowPlate extends StatefulWidget {
  final Widget child;
  final double radius;

  /// Outlines the field in red while it has a validation problem.
  final bool error;

  const _GlowPlate({required this.child, this.radius = 30, this.error = false});

  @override
  State<_GlowPlate> createState() => _GlowPlateState();
}

class _GlowPlateState extends State<_GlowPlate> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: AppTheme.glowFieldWrapper(focused: _focused).copyWith(
          borderRadius: BorderRadius.circular(widget.radius),
          border: widget.error
              ? Border.all(color: Colors.red.shade700, width: 1.4)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// One problem that stops the form from posting (see _formIssue): what to
/// tell the farmer, which section to scroll to and, for a text field, what
/// to focus.
class _FormIssue {
  final String message;
  final GlobalKey key;
  final FocusNode? focus;

  /// The product name isn't a supported commodity — answered with the
  /// Supported Products dialog rather than just an inline message.
  final bool unsupportedProduct;

  const _FormIssue(this.message, this.key, this.focus, this.unsupportedProduct);
}

/// Dashed rounded outline for the empty photo uploader.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
