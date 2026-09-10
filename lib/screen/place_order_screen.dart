import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/order_service.dart';

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
  });

  @override
  State<PlaceOrderScreen> createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  late final TextEditingController _quantityController;
  final _orderService = OrderService();

  bool _submitting = false;
  late String _deliveryMethod;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: '${widget.initialQuantity ?? widget.minimumQuantity}',
    );
    _deliveryMethod = widget.deliveryAvailable
        ? 'delivery'
        : (widget.pickupAvailable ? 'pickup' : 'unspecified');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  bool get _canChooseDelivery =>
      widget.pickupAvailable || widget.deliveryAvailable;

  num _extractUnitPrice(String raw) {
    final normalized = raw.replaceAll(',', '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(normalized);
    if (match == null) return 0;
    return num.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _extractUnitLabel(String raw) {
    final slash = raw.indexOf('/');
    if (slash == -1 || slash == raw.length - 1) return 'item';
    final tail = raw.substring(slash + 1).trim();
    return tail.isEmpty ? 'item' : tail;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (widget.sellerId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seller information is missing for this product.'),
        ),
      );
      return;
    }

    final qty = num.tryParse(_quantityController.text.trim()) ?? 1;

    // Proactive stock check so the buyer gets a friendly message instead of
    // filling out the whole form only to have the server-side transaction
    // in OrderService reject it. That transaction remains the source of
    // truth — this is just a faster, friendlier first check.
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This listing is no longer available.')),
        );
        return;
      }
      final available = (data['quantity'] as num?)?.toInt() ?? 0;
      if (qty > available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              available <= 0
                  ? 'This item is out of stock.'
                  : 'Only $available available right now. Lower your quantity.',
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // If the check itself fails (e.g. offline), fall through — the
      // Firestore transaction in OrderService still enforces this.
    }

    setState(() => _submitting = true);
    final unitPrice = _extractUnitPrice(widget.productPrice);
    final unit = _extractUnitLabel(widget.productPrice);

    final err = await _orderService.createOrder(
      sellerId: widget.sellerId,
      sellerName: widget.sellerName,
      productId: widget.productId,
      productName: widget.productName,
      imageUrl: widget.productImage,
      quantity: qty,
      unit: unit,
      unitPrice: unitPrice,
      buyerName: _nameController.text.trim(),
      buyerContact: _contactController.text.trim(),
      buyerAddress: _addressController.text.trim(),
      deliveryMethod: _canChooseDelivery ? _deliveryMethod : 'unspecified',
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
          _canChooseDelivery
              ? 'Order request sent for $_deliveryMethod.'
              : 'Order request sent.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place Order'),
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: widget.productImage.isNotEmpty
                            ? Image.network(
                                widget.productImage,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.productPrice,
                            style: const TextStyle(
                              color: _dark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Seller: ${widget.sellerName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter your name'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact Number'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a contact number'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter address'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (value) {
                  final q = num.tryParse((value ?? '').trim());
                  if (q == null || q <= 0) return 'Enter valid quantity';
                  if (q < widget.minimumQuantity) {
                    return 'Minimum for ${widget.pricingType} is ${widget.minimumQuantity}';
                  }
                  if (widget.maximumQuantity > 0 &&
                      q > widget.maximumQuantity) {
                    return 'Maximum for ${widget.pricingType} is ${widget.maximumQuantity}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              if (_canChooseDelivery)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    RadioGroup<String>(
                      groupValue: _deliveryMethod,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _deliveryMethod = value);
                        }
                      },
                      child: Column(
                        children: [
                          if (widget.pickupAvailable)
                            const RadioListTile<String>(
                              value: 'pickup',
                              title: Text('Pick-up'),
                            ),
                          if (widget.deliveryAvailable)
                            const RadioListTile<String>(
                              value: 'delivery',
                              title: Text('Delivery'),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                const Text(
                  'No pickup/delivery option is available for this product.',
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(_submitting ? 'Submitting...' : 'Submit Order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
