import 'dart:async';

import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../services/market_price_helpers.dart';
import '../services/pricing_tier_service.dart';
import '../services/connectivity_service.dart';
import '../services/delivery_coverage.dart';
import '../services/message_service.dart';
import '../services/ph_mobile.dart';
import '../data/commodity_master_list.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/buyer_location_field.dart';
import '../widgets/buyer_location_picker.dart';
import '../widgets/glow_field.dart';
import '../widgets/glow_tap_field.dart';
import 'chat_screen.dart';

class PlaceOrderScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String productId;
  final String productName;
  final String productPrice;
  final String productImage;
  final bool deliveryAvailable;
  final bool pickupAvailable;
  final String pricingType;
  final int minimumQuantity;
  final int maximumQuantity;
  final int? initialQuantity;
  // The commodity's Unit of Measurement (see commodity_master_list.dart) —
  // drives the Quantity field's label/validation and the order actually
  // created. Defaults to deriving it from productName when a caller
  // doesn't pass one explicitly.
  final String? unit;

  /// Opened from a conversation: "Message Farmer" then just closes this
  /// screen and returns a draft message (a String) to put in that chat.
  final bool fromChat;

  const PlaceOrderScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.productId,
    required this.productName,
    required this.productPrice,
    required this.productImage,
    required this.deliveryAvailable,
    required this.pickupAvailable,
    this.pricingType = 'retail',
    this.minimumQuantity = 1,
    this.maximumQuantity = 0,
    this.initialQuantity,
    this.unit,
    this.fromChat = false,
  });

  @override
  State<PlaceOrderScreen> createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _accent = Color(0xFFDCEDC8);

  // Name and contact errors appear once Submit has been tried.
  bool _showErrors = false;
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  // The buyer has to say the number shown is right and reachable before
  // ordering. Unticked again whenever the number is changed, so the tick
  // always refers to the number that is actually sent.
  bool _contactConfirmed = false;
  String _confirmedContact = '';
  final _addressController = TextEditingController();
  late final TextEditingController _quantityController;
  final _orderService = OrderService();
  final _authService = AuthService();

  bool _submitting = false;
  bool _messaging = false;
  // 'delivery' or 'pickup' — null until chosen (or auto-picked when only
  // one is possible). See _syncFulfillment.
  String? _fulfillment;
  // The listing, kept live: when the farmer adds the buyer's area to its
  // delivery coverage, delivery opens here at once.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _productSub;
  DateTime? _neededBy;
  Map<String, dynamic>? _liveProduct;
  bool _loadingProduct = true;

  // The buyer's structured location for this order — see BuyerLocationField.
  // _addressController.text (used by OrderService.createOrder's
  // buyerAddress) is kept in sync with this, so the rest of the form
  // doesn't need to know this field exists.
  BuyerLocationResult? _buyerLocation;
  bool _locationTouched = false;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: '${widget.initialQuantity ?? widget.minimumQuantity}',
    );
    _quantityController.addListener(_onQuantityChanged);
    // So their error lines clear as soon as the field is filled in.
    _nameController.addListener(_onQuantityChanged);
    _contactController.addListener(_onQuantityChanged);
    _contactController.addListener(_onContactEdited);
    _loadProduct();
    _prefillLocation();
  }

  // Best-effort: fills in the buyer's name and contact number from their
  // profile, and reuses whatever location the buyer last set on an earlier
  // order (saved via AuthService.saveBuyerLocation) so they don't have to
  // redo the Region/Province/City/Barangay picker every single order.
  Future<void> _prefillLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data();

      // Name and contact number from the buyer's own profile — a starting
      // point only: both stay editable, and nothing the buyer has already
      // typed is overwritten.
      if (mounted) {
        final name =
            [
                  data?['name'],
                  data?['fullName'],
                  FirebaseAuth.instance.currentUser?.displayName,
                ]
                .map((v) => (v ?? '').toString().trim())
                .firstWhere((v) => v.isNotEmpty, orElse: () => '');
        // Whatever format it was saved in, shown as the 10 digits after +63.
        final contact = phMobileLocalDigits(
          (data?['mobileNumber'] ?? data?['phone'])?.toString(),
        );
        if (_nameController.text.isEmpty && name.isNotEmpty) {
          _nameController.text = name;
        }
        if (_contactController.text.isEmpty && contact.isNotEmpty) {
          _contactController.text = contact;
        }
      }

      final province = data?['province']?.toString();
      final city = data?['municipality']?.toString();
      final barangay = data?['barangay']?.toString();
      if (province == null ||
          province.isEmpty ||
          city == null ||
          city.isEmpty ||
          barangay == null ||
          barangay.isEmpty) {
        return;
      }
      final region = data?['region']?.toString();

      double? lat;
      double? lng;
      try {
        final geoDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('private')
            .doc('geo')
            .get();
        lat = (geoDoc.data()?['latitude'] as num?)?.toDouble();
        lng = (geoDoc.data()?['longitude'] as num?)?.toDouble();
      } catch (_) {
        // Non-fatal — the readable address still prefills without a pin.
      }

      if (!mounted) return;
      final result = BuyerLocationResult(
        region: (region != null && region.isNotEmpty) ? region : province,
        province: province,
        city: city,
        barangay: barangay,
        latitude: lat,
        longitude: lng,
      );
      setState(() {
        _buyerLocation = result;
        _addressController.text = result.readable;
        _syncFulfillment();
      });
    } catch (_) {
      // Prefill is best-effort only — the buyer can still pick fresh.
    }
  }

  void _onLocationPicked(BuyerLocationResult result) {
    setState(() {
      _buyerLocation = result;
      _addressController.text = result.readable;
      _locationTouched = false;
      // A new area may be inside or outside the delivery coverage.
      _syncFulfillment();
    });
    // Fire-and-forget: also keeps users/{uid} up to date, so the admin
    // Demand Heatmap and the next order's prefill both stay current.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _authService.saveBuyerLocation(
        uid: uid,
        latitude: result.latitude,
        longitude: result.longitude,
        region: result.region,
        province: result.province,
        city: result.city,
        barangay: result.barangay,
      );
    }
  }

  @override
  void dispose() {
    _productSub?.cancel();
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _quantityController.removeListener(_onQuantityChanged);
    _quantityController.dispose();
    super.dispose();
  }

  // ---- Fulfillment: always from the latest listing once it has loaded ----
  bool get _offersDelivery => _liveProduct != null
      ? _liveProduct!['deliveryAvailable'] == true
      : widget.deliveryAvailable;
  bool get _offersPickup => _liveProduct != null
      ? _liveProduct!['pickupOnly'] == true
      : widget.pickupAvailable;
  bool get _canChooseDelivery => _offersDelivery || _offersPickup;

  DeliveryCoverage get _coverage =>
      DeliveryCoverage.fromProduct(_liveProduct ?? const {});

  BuyerArea get _buyerArea {
    final location = _buyerLocation;
    if (location == null) return const BuyerArea();
    return BuyerArea(
      barangay: location.barangay,
      city: location.city,
      province: location.province,
    );
  }

  DeliveryReach get _reach => _coverage.reach(_buyerArea);

  // Only where the farmer's own delivery coverage reaches: the buyer cannot
  // open delivery to an area the farmer has not added.
  bool get _deliveryAllowed =>
      _offersDelivery && _reach == DeliveryReach.covered;

  bool get _isLongDistance =>
      _fulfillment == 'delivery' && _reach != DeliveryReach.covered;

  /// The delivery fee when it's a known amount, else null (pick-up, or
  /// "to be arranged with seller").
  num? get _knownDeliveryFee =>
      _fulfillment == 'delivery' && !_isLongDistance && _coverage.feeKnown
      ? _coverage.fee
      : null;

  bool get _deliveryFeePending =>
      _fulfillment == 'delivery' && _knownDeliveryFee == null;

  // Drops a choice the listing or the buyer's location no longer allows,
  // and picks the only possible option when there's just one.
  void _syncFulfillment() {
    if (_fulfillment == 'delivery' && !_deliveryAllowed) _fulfillment = null;
    if (_fulfillment == 'pickup' && !_offersPickup) _fulfillment = null;
    if (_fulfillment == null) {
      if (_deliveryAllowed && !_offersPickup) {
        _fulfillment = 'delivery';
      } else if (_offersPickup && !_deliveryAllowed) {
        _fulfillment = 'pickup';
      }
    }
  }

  // What the summary shows — compared before and after the final re-check
  // so the buyer never submits numbers they didn't see.
  String get _summarySignature {
    final quote = _currentQuote;
    return [
      quote.unitPrice,
      quote.pricingType,
      _fulfillment,
      _knownDeliveryFee,
      _reach.name,
      _offersDelivery,
      _offersPickup,
    ].join('|');
  }

  void _onQuantityChanged() {
    if (mounted) setState(() {});
  }

  void _loadProduct() {
    _productSub = FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _liveProduct = snap.data();
              _loadingProduct = false;
              _syncFulfillment();
            });
          },
          onError: (_) {
            if (mounted) setState(() => _loadingProduct = false);
          },
        );
  }

  PricingTierQuote get _currentQuote {
    final data = _liveProduct;
    final qty = num.tryParse(_quantityController.text.trim()) ?? 0;
    final retail =
        (data?['retailPrice'] as num?) ??
        (data?['price'] as num?) ??
        _extractUnitPrice(widget.productPrice);
    final wholesaleEnabled = data != null
        ? PricingTierService.wholesaleAvailable(data)
        : widget.pricingType == 'wholesale';
    final wholesalePrice = data?['wholesalePrice'] as num?;
    final wholesaleMinimum = data?['wholesaleMinimumQuantity'] as num?;

    return PricingTierService.quote(
      quantity: qty,
      retailPrice: retail,
      wholesaleEnabled: wholesaleEnabled,
      wholesalePrice: wholesalePrice,
      wholesaleMinimumQuantity: wholesaleMinimum,
    );
  }

  // When the buyer chose Wholesale (e.g. from an order-options message), the
  // listing's current wholesale minimum is enforced; retail orders keep the
  // normal rules.
  num? get _wholesaleMinimum {
    if (widget.pricingType != 'wholesale') return null;
    final live = _liveProduct?['wholesaleMinimumQuantity'] as num?;
    return live ?? widget.minimumQuantity;
  }

  // The commodity's real Unit of Measurement (see commodity_master_list.dart)
  // — explicit widget.unit wins when a caller passes it, otherwise derived
  // from the product name so this never depends on parsing a display string.
  String get _unit => widget.unit ?? unitForProductName(widget.productName);
  bool get _isCountBasedUnit => isCountBasedUnit(_unit);

  num _extractUnitPrice(String raw) {
    final normalized = raw.replaceAll(',', '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(normalized);
    if (match == null) return 0;
    return num.tryParse(match.group(1) ?? '') ?? 0;
  }

  void _onContactEdited() {
    if (_contactConfirmed && _contactController.text != _confirmedContact) {
      setState(() => _contactConfirmed = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_nameError != null ||
        !_contactValid ||
        !_contactConfirmed ||
        _quantityError != null) {
      setState(() => _showErrors = true);
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      setState(() => _locationTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your location.')),
      );
      return;
    }
    if (widget.sellerId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seller information is missing for this product.'),
        ),
      );
      return;
    }
    if (_canChooseDelivery && _fulfillment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose delivery or pick-up.')),
      );
      return;
    }

    final qty = num.tryParse(_quantityController.text.trim()) ?? 1;
    setState(() => _submitting = true);

    if (!await ConnectivityService.instance.checkNow()) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      return;
    }

    // Final check against the latest listing — status, stock, price tier,
    // delivery/pick-up, coverage and fee — so the buyer gets a friendly
    // message (or a refreshed summary) instead of a surprise. The
    // transaction in OrderService still enforces stock and fulfillment.
    try {
      final productSnap = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .get();
      final data = productSnap.data();
      if (!productSnap.exists ||
          data == null ||
          data['isArchived'] == true ||
          data['isSuspended'] == true) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available.')),
        );
        return;
      }
      final available = (data['quantity'] as num?) ?? 0;
      if (qty > available) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              available <= 0
                  ? 'This item is out of stock.'
                  : 'Only ${formatStock(available, _unit)} available right now. Lower your quantity.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      final before = _summarySignature;
      setState(() {
        _liveProduct = data;
        _syncFulfillment();
      });
      if (_summarySignature != before) {
        setState(() => _submitting = false);
        await showAgriDialog<void>(
          context: context,
          builder: (dialogContext) => AgriDialog(
            icon: Icons.update_rounded,
            tone: AgriTone.warning,
            title: const Text('Order details updated'),
            content: const Text(
              'The seller changed this listing (price, delivery or pick-up) '
              'since you opened it. Please review the updated summary before '
              'submitting.',
            ),
            actions: [
              AgriDialogButton(
                label: 'Review',
                kind: AgriButtonKind.primary,
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
        return;
      }
    } catch (_) {
      // If the check itself fails (e.g. offline), fall through — the
      // Firestore transaction in OrderService still enforces this.
    }

    final quote = _currentQuote;
    final method = _canChooseDelivery
        ? (_fulfillment ?? 'unspecified')
        : 'unspecified';

    final err = await _orderService.createOrder(
      sellerId: widget.sellerId,
      sellerName: widget.sellerName,
      productId: widget.productId,
      productName: widget.productName,
      imageUrl: widget.productImage,
      quantity: qty,
      unitPrice: quote.unitPrice,
      buyerName: _nameController.text.trim(),
      // Always +639XXXXXXXXX.
      buyerContact: phMobileE164(_contactController.text.trim()),
      buyerAddress: _addressController.text.trim(),
      deliveryMethod: method,
      neededBy: _neededBy,
      buyerArea: _buyerArea,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          method == 'unspecified'
              ? 'Order request sent.'
              : 'Order request sent for ${method == 'pickup' ? 'pick-up' : 'delivery'}.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  // Outside the standard coverage: hand the buyer to Messages with a draft
  // asking about long-distance delivery. From a chat, this screen just
  // closes and returns the draft (see startChatOrder); otherwise it opens
  // the conversation with this farmer about this product.
  Future<void> _messageFarmer() async {
    if (_messaging) return;
    final qty = num.tryParse(_quantityController.text.trim());
    final amount = qty == null || qty <= 0
        ? ''
        : '${formatStock(qty, _unit)} of ';
    final area = _buyerArea.label;
    final draft =
        'Hi! I\'d like to order $amount${widget.productName}. I\'m in '
        '${area.isEmpty ? 'an area' : area}, which is outside your usual '
        'delivery area. Can you arrange delivery here, and how much would '
        'the delivery fee be?';

    if (widget.fromChat) {
      Navigator.pop(context, draft);
      return;
    }

    setState(() => _messaging = true);
    try {
      final product = _liveProduct ?? const <String, dynamic>{};
      final conversationId = await MessageService().startOrGetConversation(
        otherUserId: widget.sellerId,
        otherUserName: widget.sellerName,
        productId: widget.productId,
        productName: widget.productName,
        productImageUrl: widget.productImage,
        retailPrice:
            (product['retailPrice'] as num?) ?? (product['price'] as num?),
        wholesalePrice: product['wholesalePrice'] as num?,
        wholesaleMinimumQuantity:
            (product['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
        unit: _unit,
        deliveryAvailable: _offersDelivery,
        pickupOnly: _offersPickup,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: widget.sellerId,
            otherUserName: widget.sellerName,
            productId: widget.productId,
            productName: widget.productName,
            productImageUrl: widget.productImage,
            initialDraft: draft,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Messages. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _messaging = false);
    }
  }

  // ---- Field validation ----
  // Shown under each field (the Registration pattern — see _field), once
  // the buyer has tried to submit; the quantity is checked as they type.
  String? get _nameError =>
      _nameController.text.trim().isEmpty ? 'Enter your name' : null;

  // A contact number is required to order. A wrong first digit shows as
  // it is typed; "required" and "not all 10 digits" after Submit — the
  // same rules as every other mobile field (see ph_mobile.dart).
  String? get _contactError => phMobileError(
    _contactController.text.trim(),
    required: true,
    submitted: _showErrors,
  );

  bool get _contactValid => isValidPhMobile(_contactController.text.trim());

  String? get _quantityError {
    final q = num.tryParse(_quantityController.text.trim());
    if (q == null || q <= 0) return 'Enter valid quantity';
    if (_isCountBasedUnit && q != q.roundToDouble()) {
      return 'Quantity for $_unit must be a whole number';
    }
    final wholesaleMinimum = _wholesaleMinimum;
    if (wholesaleMinimum != null && q < wholesaleMinimum) {
      return 'Wholesale orders need at least '
          '${formatStock(wholesaleMinimum, _unit)}';
    }
    // The same stock check _submit makes against the latest listing, shown
    // early so the buyer doesn't find out only after tapping Submit.
    final available = _liveProduct?['quantity'] as num?;
    if (available != null && q > available) {
      return available <= 0
          ? 'This item is out of stock.'
          : 'Only ${formatStock(available, _unit)} available right now.';
    }
    return null;
  }

  static const Color _pageBackground = AppTheme.surface;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: const AgriAppBar(title: 'Place Order'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _productSummary(),
            const SizedBox(height: 22),

            _sectionTitle('Buyer Details'),
            const SizedBox(height: 12),
            _field(
              label: 'Name',
              errorText: _showErrors ? _nameError : null,
              child: GlowField(
                controller: _nameController,
                hint: 'Your full name',
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
              ),
            ),
            // Has its own label, error line and bottom spacing.
            BuyerLocationField(
              label: 'Address',
              value: _buyerLocation,
              errorText: _locationTouched && _buyerLocation == null
                  ? 'Please set your location.'
                  : null,
              onPicked: _onLocationPicked,
            ),
            const SizedBox(height: 6),

            // Starts from the number on the buyer's profile (_prefill…);
            // what is typed here goes on this order only and never back
            // to the profile.
            _sectionTitle('Contact Information'),
            const SizedBox(height: 12),
            _field(
              label: 'Contact Number',
              errorText: _contactError,
              caption:
                  'Used for this order only. Changing it here does not '
                  'change the number on your profile.',
              child: GlowField(
                controller: _contactController,
                hint: kPhMobileHint,
                // Fixed and not editable; only the 10 digits after it are.
                prefixText: kPhMobilePrefix,
                inputFormatters: kPhMobileInputFormatters,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
            ),
            _contactConfirmation(),
            const SizedBox(height: 6),

            _sectionTitle('Order'),
            const SizedBox(height: 12),
            _field(
              label: 'Ordered Quantity ($_unit)',
              errorText: _quantityError,
              child: GlowField(
                controller: _quantityController,
                hint: 'How many $_unit',
                icon: Icons.scale_outlined,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: !_isCountBasedUnit,
                ),
              ),
            ),
            _field(
              label: 'Needed by (Optional)',
              caption:
                  'Your preferred date. The farmer will confirm whether it '
                  'can be met.',
              child: GlowTapField(
                icon: Icons.calendar_today_outlined,
                value: _neededBy == null
                    ? null
                    : '${_neededBy!.month}/${_neededBy!.day}/${_neededBy!.year}',
                hint: 'No specific date',
                onTap: _pickNeededBy,
              ),
            ),

            if (!_loadingProduct) ...[
              _pricingCard(),
              const SizedBox(height: 18),
            ],
            _fulfillmentSection(),
            const SizedBox(height: 18),
            if (!_loadingProduct) _orderSummary(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: !_submitting ? _submit : null,
            // The app's standard pill button (dark green, white text).
            style: AppTheme.primaryButton(),
            child: Text(
              _submitting ? 'Submitting...' : 'Submit Order',
              style: AppTheme.buttonText(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickNeededBy() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      // Any date from today on — next year included. It is only a
      // preference, so there is no tight window to enforce.
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) {
      setState(() => _neededBy = picked);
    }
  }

  Widget _sectionTitle(String text) => Text(text, style: AppTheme.heading(16));

  // "This number is correct and reachable" — required before ordering.
  Widget _contactConfirmation() {
    final showError = _showErrors && _contactValid && !_contactConfirmed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _setContactConfirmed(!_contactConfirmed),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _contactConfirmed,
              onChanged: (v) => _setContactConfirmed(v ?? false),
              activeColor: AppTheme.dark,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I confirm this contact number is correct and that I '
                      'can be reached on it.',
                      style: AppTheme.body(
                        color: Colors.black87,
                        size: 12.5,
                      ).copyWith(height: 1.4),
                    ),
                    if (showError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Please confirm your contact number to continue.',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11.5,
                          ),
                        ),
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

  void _setContactConfirmed(bool value) {
    setState(() {
      _contactConfirmed = value;
      _confirmedContact = _contactController.text;
    });
  }

  // Label above, pill field, error line below — exactly how the
  // Registration form lays out each of its fields (see RegisterScreen).
  Widget _field({
    required String label,
    required Widget child,
    String? errorText,
    String? caption,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.label()),
          const SizedBox(height: 8),
          child,
          if (errorText != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
          if (errorText == null && caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );

  // ---- Product summary: image, name, the price that applies, seller ----
  Widget _productSummary() {
    final quote = _currentQuote;
    Widget placeholder() => Container(
      color: _accent,
      child: const Icon(Icons.shopping_basket, color: _dark),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 68,
              height: 68,
              child: widget.productImage.isNotEmpty
                  ? Image.network(
                      widget.productImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => placeholder(),
                    )
                  : placeholder(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loadingProduct
                      ? widget.productPrice
                      : formatPriceWithUnit(quote.unitPrice, _unit),
                  style: const TextStyle(
                    fontSize: 15,
                    color: _dark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _loadingProduct
                      ? 'Checking pricing…'
                      : quote.isWholesale
                      ? 'Wholesale price applied'
                      : 'Retail price applied',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: quote.isWholesale ? _dark : Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Seller: ${widget.sellerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Which price applies, and how far wholesale is ----
  Widget _pricingCard() {
    final quote = _currentQuote;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: quote.isWholesale
            ? Colors.green[50]
            : _accent.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: quote.isWholesale ? Colors.green[200]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote.isWholesale
                ? 'Wholesale price applied'
                : 'Retail price applied',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatStock(quote.quantity, _unit)} × '
            '${formatPriceWithUnit(quote.unitPrice, _unit)} '
            '= ${formatPeso(quote.subtotal)}',
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          if (!quote.isWholesale &&
              quote.quantityToWholesale != null &&
              quote.quantityToWholesale! > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Add ${formatStock(quote.quantityToWholesale!, _unit)} more '
              'to qualify for the wholesale price.',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Fulfillment: Delivery / Pick-up ----
  Widget _fulfillmentSection() {
    if (_loadingProduct) {
      return Text(
        'Checking delivery and pick-up options…',
        style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
      );
    }
    if (!_canChooseDelivery) {
      return Text(
        'This seller hasn\'t set delivery or pick-up for this product. You '
        'can arrange it with them after ordering.',
        style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
      );
    }

    final coverage = _coverage;
    final reach = _reach;
    final String deliverySubtitle = switch (reach) {
      DeliveryReach.covered =>
        'Delivers to ${coverage.areaLabel} · Fee: ${coverage.feeLabel}',

      _ => 'Standard coverage: ${coverage.areaLabel}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Fulfillment'),
        const SizedBox(height: 10),
        if (_offersDelivery)
          _fulfillmentOption(
            value: 'delivery',
            icon: Icons.local_shipping_outlined,
            title: 'Delivery',
            subtitle: deliverySubtitle,
            enabled: _deliveryAllowed,
          ),
        if (_offersDelivery && reach == DeliveryReach.unknownLocation)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Set your address above to check whether delivery reaches you.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        if (_offersDelivery && reach == DeliveryReach.outside)
          _outsideCoverageCard(),
        if (_offersPickup)
          _fulfillmentOption(
            value: 'pickup',
            icon: Icons.storefront_outlined,
            title: 'Pick-up',
            subtitle:
                'Collect from the farmer in ${coverage.origin.name}. '
                'No delivery fee.',
            enabled: true,
          ),
      ],
    );
  }

  Widget _fulfillmentOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
  }) {
    final selected = _fulfillment == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? () => setState(() => _fulfillment = value) : null,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.tint : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _dark : Colors.grey.shade300,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? _dark : Colors.grey[500],
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20, color: _dark),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Outside the farmer's delivery coverage: delivery is not offered, and
  // the buyer cannot open it themselves. They can pick it up instead, or
  // ask the farmer to add their area — once the farmer does, delivery opens
  // here by itself (the listing is kept live).
  //
  // Two small, equal buttons — Message and Choose Pick-up — which go away
  // once Pick-up is chosen (the choice is made; only the note stays).
  Widget _outsideCoverageCard() {
    final warning = Colors.orange.shade800;
    final pickedUp = _fulfillment == 'pickup';
    const pillShape = StadiumBorder();
    const compact = Size(0, 36);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12);
    const buttonText = TextStyle(
      fontFamily: 'Montserrat',
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.location_off_outlined, size: 18, color: warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Delivery doesn't reach your area",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pickedUp
                ? 'You chose pick-up for this order.'
                : _offersPickup
                ? 'Pick it up instead, or ask the farmer to add your area.'
                : 'Ask the farmer to add your area to their delivery.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
          ),
          if (!pickedUp) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _messaging ? null : _messageFarmer,
                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dark,
                      side: const BorderSide(color: _dark),
                      minimumSize: compact,
                      padding: buttonPadding,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: buttonText,
                      shape: pillShape,
                    ),
                  ),
                ),
                if (_offersPickup) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _fulfillment = 'pickup'),
                      icon: const Icon(Icons.storefront_outlined, size: 15),
                      label: const Text('Choose Pick-up'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _dark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: compact,
                        padding: buttonPadding,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: buttonText,
                        shape: pillShape,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- Order summary (what the buyer is about to submit) ----
  Widget _orderSummary() {
    final quote = _currentQuote;
    final fee = _knownDeliveryFee;
    final String fulfillmentLabel = switch (_fulfillment) {
      'delivery' when _isLongDistance => 'Delivery (long-distance, arranged)',
      'delivery' => 'Delivery',
      'pickup' => 'Pick-up',
      _ =>
        _canChooseDelivery ? 'Not selected yet' : 'To be arranged with seller',
    };

    final String? total;
    final String? totalNote;
    if (_canChooseDelivery && _fulfillment == null) {
      total = null;
      totalNote = 'Choose delivery or pick-up to see your total.';
    } else if (_deliveryFeePending) {
      total = null;
      totalNote =
          'Product subtotal ${formatPeso(quote.subtotal)} + delivery fee. '
          'The final total will be confirmed with the seller.';
    } else if (!_canChooseDelivery) {
      total = null;
      totalNote =
          'Product subtotal ${formatPeso(quote.subtotal)}. Any delivery cost '
          'is arranged with the seller.';
    } else {
      total = formatPeso(quote.subtotal + (fee ?? 0));
      totalNote = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _summaryRow('Product', widget.productName),
          _summaryRow('Order type', quote.isWholesale ? 'Wholesale' : 'Retail'),
          _summaryRow('Quantity', formatStock(quote.quantity, _unit)),
          _summaryRow(
            'Unit price',
            formatPriceWithUnit(quote.unitPrice, _unit),
          ),
          _summaryRow('Product subtotal', formatPeso(quote.subtotal)),
          if (_fulfillment == 'delivery')
            _summaryRow(
              'Delivery fee',
              fee != null ? formatPeso(fee) : 'To be arranged with seller',
              emphasize: fee == null,
            ),
          _summaryRow('Fulfillment', fulfillmentLabel),
          const Divider(height: 18),
          if (total != null)
            _summaryRow('Total', total, bold: true)
          else
            Text(
              totalNote ?? '',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[700],
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: bold ? 18 : 13,
                fontWeight: bold || emphasize
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: bold
                    ? _dark
                    : emphasize
                    ? Colors.orange.shade800
                    : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
