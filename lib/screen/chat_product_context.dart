import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/commodity_master_list.dart';
import '../services/delivery_coverage.dart';
import '../services/market_price_helpers.dart';
import '../services/pricing_tier_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import 'add_product_screen.dart';
import 'place_order_screen.dart';

// Product context for a Farmer–Buyer conversation that's tied to a product,
// shared by ChatScreen and MessageOrderScreen:
//  - ChatProductCard: the card pinned above the messages (Order Now for the
//    buyer; View Listing + Send Options for the farmer).
//  - showSendOrderOptionsSheet: the farmer's Send Options confirmation.
//  - OrderOptionsMessageCard: the order-options message in the thread
//    (type 'pricingOptions'), with Choose Retail / Choose Wholesale for
//    the buyer and a read-only record for the farmer.
//  - startChatOrder: re-checks the latest product, then opens the existing
//    PlaceOrderScreen — no order logic lives in Messages.

const Color _border = Color(0xFFDCEDC8);

/// The current state of a product listing, read from products/{id}.
class ChatProduct {
  final String id;
  final String name;
  final String imageUrl;
  final String unit;
  final String farmerId;
  final String farmerName;
  final num retailPrice;
  final bool wholesaleEnabled;
  final num? wholesalePrice;
  final num? wholesaleMinimum;
  final num stock;
  final bool listed;
  final bool deliveryAvailable;
  final bool pickupAvailable;
  final Map<String, dynamic> data;

  const ChatProduct._({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.unit,
    required this.farmerId,
    required this.farmerName,
    required this.retailPrice,
    required this.wholesaleEnabled,
    required this.wholesalePrice,
    required this.wholesaleMinimum,
    required this.stock,
    required this.listed,
    required this.deliveryAvailable,
    required this.pickupAvailable,
    required this.data,
  });

  factory ChatProduct.fromData(String id, Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Product').toString();
    final unitRaw = data['unit']?.toString().trim() ?? '';
    final imageUrls = data['imageUrls'];
    final imageUrl = (data['imageUrl']?.toString().isNotEmpty ?? false)
        ? data['imageUrl'].toString()
        : (imageUrls is List && imageUrls.isNotEmpty)
        ? imageUrls.first.toString()
        : '';
    final wholesaleEnabled = PricingTierService.wholesaleAvailable(data);
    return ChatProduct._(
      id: id,
      name: name,
      imageUrl: imageUrl,
      unit: unitRaw.isNotEmpty ? unitRaw : unitForProductName(name),
      farmerId: (data['farmerId'] ?? '').toString(),
      farmerName: (data['farmerName'] ?? '').toString(),
      retailPrice:
          (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0,
      wholesaleEnabled: wholesaleEnabled,
      wholesalePrice: wholesaleEnabled ? data['wholesalePrice'] as num? : null,
      wholesaleMinimum: wholesaleEnabled
          ? data['wholesaleMinimumQuantity'] as num?
          : null,
      stock: (data['quantity'] as num?) ?? 0,
      listed: data['isArchived'] != true && data['isSuspended'] != true,
      deliveryAvailable: data['deliveryAvailable'] == true,
      pickupAvailable: data['pickupOnly'] == true,
      data: data,
    );
  }

  bool get inStock => stock > 0;
  bool get orderable => listed && inStock && retailPrice > 0;

  String get retailLabel => formatPriceWithUnit(retailPrice, unit);
  String get wholesaleLabel => formatPriceWithUnit(wholesalePrice ?? 0, unit);
  String get minimumLabel => formatStock(wholesaleMinimum ?? 0, unit);

  num priceFor(String pricingType) =>
      pricingType == 'wholesale' ? (wholesalePrice ?? 0) : retailPrice;

  DeliveryCoverage get coverage => DeliveryCoverage.fromProduct(data);

  /// e.g. "Delivery: Within Laurel · ₱50.00" or "Delivery: not offered".
  String get deliveryLabel => deliveryAvailable
      ? 'Delivery: ${coverage.areaLabel} · '
            '${coverage.feeKnown ? coverage.feeLabel : 'fee to be arranged'}'
      : 'Delivery: not offered';

  String get pickupLabel =>
      pickupAvailable ? 'Pick-up available' : 'Pick-up: not offered';
}

Future<ChatProduct?> fetchChatProduct(String productId) async {
  final snap = await FirebaseFirestore.instance
      .collection('products')
      .doc(productId)
      .get();
  final data = snap.data();
  return data == null ? null : ChatProduct.fromData(snap.id, data);
}

String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Checks the latest product data, then opens the existing order flow
/// (PlaceOrderScreen), where the buyer picks delivery or pick-up and the
/// delivery coverage, fee and everything else is validated again.
///
/// [pricingType] is null for a plain Order Now (the order screen picks the
/// tier from the quantity), or 'retail'/'wholesale' when the buyer chose an
/// option from an order-options message. [quotedPrice] is the price that
/// message showed, so the buyer is told if it has changed since.
///
/// Resolves to a draft message when the buyer tapped Message Farmer (to ask
/// about delivery outside the farmer's coverage) — the caller puts it in
/// the chat's composer — otherwise null.
Future<String?> startChatOrder(
  BuildContext context, {
  required String productId,
  required String sellerId,
  required String sellerName,
  String? pricingType,
  num? quotedPrice,
}) async {
  if (productId.isEmpty) {
    _snack(context, 'This product is no longer available.');
    return null;
  }

  ChatProduct? product;
  try {
    product = await fetchChatProduct(productId);
  } catch (_) {
    if (context.mounted) {
      _snack(
        context,
        'Could not load the latest product details. Check your connection and try again.',
      );
    }
    return null;
  }
  if (!context.mounted) return null;

  if (product == null || !product.listed || product.retailPrice <= 0) {
    await _notice(
      context,
      title: 'Listing unavailable',
      message: 'This product is no longer available for ordering.',
    );
    return null;
  }
  if (product.farmerId.isNotEmpty && product.farmerId == _myUid) {
    _snack(context, 'You can\'t order your own product.');
    return null;
  }
  if (!product.inStock) {
    await _notice(
      context,
      title: 'Out of stock',
      message: '${product.name} is currently out of stock.',
    );
    return null;
  }

  var type = pricingType;
  if (type == 'wholesale') {
    final String? reason = !product.wholesaleEnabled
        ? 'The farmer no longer offers wholesale for ${product.name}.'
        : product.stock < (product.wholesaleMinimum ?? 0)
        ? 'Only ${formatStock(product.stock, product.unit)} is left — less '
              'than the wholesale minimum of ${product.minimumLabel}.'
        : null;
    if (reason != null) {
      final retail = await showAgriConfirm(
        context: context,
        icon: Icons.info_outline_rounded,
        tone: AgriTone.warning,
        title: 'Wholesale unavailable',
        message:
            '$reason You can still order at the retail price of '
            '${product.retailLabel}.',
        confirmLabel: 'Order Retail',
      );
      if (!retail || !context.mounted) return null;
      type = 'retail';
      quotedPrice = null;
    }
  }

  if (type != null && quotedPrice != null) {
    final current = product.priceFor(type);
    if ((current - quotedPrice).abs() > 0.001) {
      final proceed = await showAgriConfirm(
        context: context,
        icon: Icons.sell_outlined,
        tone: AgriTone.warning,
        title: 'Price updated',
        message:
            'The ${type == 'wholesale' ? 'wholesale' : 'retail'} price of '
            '${product.name} changed from '
            '${formatPriceWithUnit(quotedPrice, product.unit)} to '
            '${formatPriceWithUnit(current, product.unit)} since these '
            'options were sent. Continue at the current price?',
        confirmLabel: 'Continue',
      );
      if (!proceed || !context.mounted) return null;
    }
  }

  final listing = product;
  final wholesale = type == 'wholesale';
  final minimum = wholesale ? (listing.wholesaleMinimum ?? 1).ceil() : 1;
  final result = await Navigator.push<Object?>(
    context,
    MaterialPageRoute(
      builder: (_) => PlaceOrderScreen(
        sellerId: listing.farmerId.isNotEmpty ? listing.farmerId : sellerId,
        sellerName: listing.farmerName.isNotEmpty
            ? listing.farmerName
            : sellerName,
        productId: listing.id,
        productName: listing.name,
        productPrice: formatPriceWithUnit(
          listing.priceFor(type ?? 'retail'),
          listing.unit,
        ),
        productImage: listing.imageUrl,
        deliveryAvailable: listing.deliveryAvailable,
        pickupAvailable: listing.pickupAvailable,
        pricingType: type ?? 'retail',
        minimumQuantity: minimum,
        initialQuantity: wholesale ? minimum : null,
        unit: listing.unit,
        fromChat: true,
      ),
    ),
  );
  return result is String ? result : null;
}

Future<void> _notice(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showAgriDialog<void>(
    context: context,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.info_outline_rounded,
      tone: AgriTone.warning,
      title: Text(title),
      content: Text(message),
      actions: [
        AgriDialogButton(
          label: 'OK',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
}

/// The farmer's Send Options sheet: previews the order types this product
/// offers at its current prices. Resolves true when the farmer taps Send.
Future<bool> showSendOrderOptionsSheet(
  BuildContext context,
  ChatProduct product,
) async {
  final send = await showAgriSheet<bool>(
    context: context,
    title: 'Send order options',
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The buyer can choose one of these for ${product.name}:',
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          _OptionTile(label: 'Retail', price: product.retailLabel),
          if (product.wholesaleEnabled) ...[
            const SizedBox(height: 8),
            _OptionTile(
              label: 'Wholesale',
              price: product.wholesaleLabel,
              note: 'Minimum: ${product.minimumLabel}',
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Wholesale is off for this listing, so only Retail will be sent.',
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _FulfillmentLines(
            delivery: product.deliveryLabel,
            pickup: product.pickupLabel,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AgriDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(sheetContext, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AgriDialogButton(
                  label: 'Send',
                  kind: AgriButtonKind.primary,
                  onPressed: () => Navigator.pop(sheetContext, true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return send == true;
}

class _OptionTile extends StatelessWidget {
  final String label;
  final String price;
  final String? note;

  const _OptionTile({required this.label, required this.price, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            price,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.dark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Delivery and pick-up availability, one short line each.
class _FulfillmentLines extends StatelessWidget {
  final String delivery;
  final String pickup;
  final bool compact;

  const _FulfillmentLines({
    required this.delivery,
    required this.pickup,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Padding(
      padding: EdgeInsets.only(top: compact ? 1 : 3),
      child: Row(
        children: [
          Icon(icon, size: compact ? 13 : 15, color: AppTheme.dark),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontSize: compact ? 11 : 11.5,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line(Icons.local_shipping_outlined, delivery),
        line(Icons.storefront_outlined, pickup),
      ],
    );
  }
}

/// The product card pinned at the top of a product-linked conversation.
/// Follows the listing live, so prices and availability stay current.
/// Whether the viewer is the farmer comes from the product's owner once it
/// loads ([viewerIsFarmer] is only the guess until then).
class ChatProductCard extends StatefulWidget {
  final String productId;
  final String fallbackName;
  final String? fallbackImageUrl;
  final Uint8List? fallbackImageBytes;
  final String sellerId;
  final String sellerName;
  final bool viewerIsFarmer;

  /// Farmer only: called after the farmer confirms Send Options.
  final Future<void> Function(ChatProduct product)? onSendOptions;

  /// Buyer only: tapping the card's details (e.g. to start a negotiation).
  final VoidCallback? onTapDetails;

  /// Buyer only: receives the draft when the buyer taps Message Farmer in
  /// the order flow (see [startChatOrder]), to put in the composer.
  final ValueChanged<String>? onDraftMessage;

  const ChatProductCard({
    super.key,
    required this.productId,
    required this.fallbackName,
    this.fallbackImageUrl,
    this.fallbackImageBytes,
    required this.sellerId,
    required this.sellerName,
    required this.viewerIsFarmer,
    this.onSendOptions,
    this.onTapDetails,
    this.onDraftMessage,
  });

  @override
  State<ChatProductCard> createState() => _ChatProductCardState();
}

class _ChatProductCardState extends State<ChatProductCard> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream = _watch();
  bool _busy = false;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _watch() =>
      widget.productId.isEmpty
      ? null
      : FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .snapshots();

  @override
  void didUpdateWidget(ChatProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) _stream = _watch();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewListing(ChatProduct product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddProductScreen(productId: product.id, existingData: product.data),
      ),
    );
  }

  Future<void> _sendOptions(ChatProduct product) async {
    if (!product.listed) {
      _snack(
        context,
        'This listing is unavailable, so options can\'t be sent.',
      );
      return;
    }
    if (product.retailPrice <= 0) {
      _snack(context, 'Set a retail price on this listing first.');
      return;
    }
    final confirmed = await showSendOrderOptionsSheet(context, product);
    if (!confirmed || !mounted) return;
    await widget.onSendOptions?.call(product);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final product = data == null
            ? null
            : ChatProduct.fromData(widget.productId, data);
        final isFarmer = product != null && product.farmerId.isNotEmpty
            ? product.farmerId == _myUid
            : widget.viewerIsFarmer;
        return _card(product, isFarmer, loaded: snapshot.hasData);
      },
    );
  }

  Widget _card(ChatProduct? product, bool isFarmer, {required bool loaded}) {
    final name = product?.name ?? widget.fallbackName;
    final missing = loaded && product == null;
    final String? status = missing || (product != null && !product.listed)
        ? 'No longer available'
        : (product != null && !product.inStock)
        ? 'Out of stock'
        : null;

    final details = Row(
      children: [
        _image(product),
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
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              if (product != null)
                Text(
                  product.retailLabel,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dark,
                  ),
                )
              else if (!loaded)
                Text(
                  'Loading price…',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              if (product != null && product.wholesaleEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Wholesale ${product.wholesaleLabel} · min ${product.minimumLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              if (product != null)
                _FulfillmentLines(
                  delivery: product.deliveryLabel,
                  pickup: product.pickupLabel,
                  compact: true,
                ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    status,
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isFarmer) ...[
          const SizedBox(width: 8),
          _button(
            label: 'Order Now',
            primary: true,
            onPressed: product == null || !product.orderable
                ? null
                : () => _run(() async {
                    final draft = await startChatOrder(
                      context,
                      productId: widget.productId,
                      sellerId: widget.sellerId,
                      sellerName: widget.sellerName,
                    );
                    if (draft != null) widget.onDraftMessage?.call(draft);
                  }),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isFarmer && widget.onTapDetails != null)
            InkWell(
              onTap: widget.onTapDetails,
              borderRadius: BorderRadius.circular(12),
              child: details,
            )
          else
            details,
          if (isFarmer) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _button(
                    label: 'View Listing',
                    icon: Icons.storefront_outlined,
                    onPressed: product == null
                        ? null
                        : () => _viewListing(product),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _button(
                    label: 'Send Options',
                    icon: Icons.sell_outlined,
                    primary: true,
                    onPressed: product == null
                        ? null
                        : () => _run(() => _sendOptions(product)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _image(ChatProduct? product) {
    final url = product?.imageUrl.isNotEmpty == true
        ? product!.imageUrl
        : widget.fallbackImageUrl;
    const placeholder = ColoredBox(
      color: _border,
      child: Icon(Icons.eco_rounded, color: AppTheme.dark),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 58,
        height: 58,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              )
            : widget.fallbackImageBytes != null
            ? Image.memory(widget.fallbackImageBytes!, fit: BoxFit.cover)
            : placeholder,
      ),
    );
  }

  Widget _button({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool primary = false,
  }) {
    final style = primary
        ? ElevatedButton.styleFrom(
            backgroundColor: AppTheme.dark,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AppTheme.dark,
            side: const BorderSide(color: AppTheme.dark),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          );
    final text = Text(
      label,
      style: GoogleFonts.montserrat(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
    final busyOnPressed = _busy ? null : onPressed;
    if (primary) {
      return icon == null
          ? ElevatedButton(onPressed: busyOnPressed, style: style, child: text)
          : ElevatedButton.icon(
              onPressed: busyOnPressed,
              style: style,
              icon: Icon(icon, size: 16),
              label: text,
            );
    }
    return icon == null
        ? OutlinedButton(onPressed: busyOnPressed, style: style, child: text)
        : OutlinedButton.icon(
            onPressed: busyOnPressed,
            style: style,
            icon: Icon(icon, size: 16),
            label: text,
          );
  }
}

/// An order-options message ('pricingOptions') in the thread. The buyer can
/// choose Retail or Wholesale from it; the farmer who sent it sees the same
/// card as a read-only record. The prices shown are the ones that were
/// sent — [startChatOrder] re-checks them against the listing.
///
/// Older messages didn't store the product, so [fallbackProductId],
/// [fallbackProductName] and [fallbackUnit] fill in from the conversation.
class OrderOptionsMessageCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String sellerId;
  final String sellerName;
  final String? fallbackProductId;
  final String? fallbackProductName;
  final String? fallbackUnit;

  /// Receives the draft when the buyer taps Message Farmer in the order
  /// flow (see [startChatOrder]).
  final ValueChanged<String>? onDraftMessage;

  const OrderOptionsMessageCard({
    super.key,
    required this.data,
    required this.sellerId,
    required this.sellerName,
    this.fallbackProductId,
    this.fallbackProductName,
    this.fallbackUnit,
    this.onDraftMessage,
  });

  @override
  State<OrderOptionsMessageCard> createState() =>
      _OrderOptionsMessageCardState();
}

class _OrderOptionsMessageCardState extends State<OrderOptionsMessageCard> {
  bool _busy = false;

  Future<void> _choose(String productId, String type, num price) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final draft = await startChatOrder(
        context,
        productId: productId,
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        pricingType: type,
        quotedPrice: price,
      );
      if (draft != null) widget.onDraftMessage?.call(draft);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isMe = data['senderId'] == _myUid;
    final productId = (data['productId'] ?? widget.fallbackProductId ?? '')
        .toString();
    final productName =
        (data['productName'] ?? widget.fallbackProductName ?? 'Product')
            .toString();
    final unitRaw = (data['unit'] ?? widget.fallbackUnit ?? '').toString();
    final unit = unitRaw.isNotEmpty ? unitRaw : unitForProductName(productName);
    final retailPrice = (data['retailPrice'] as num?) ?? 0;
    final wholesalePrice = data['wholesalePrice'] as num?;
    final minimum = (data['wholesaleMinimumQuantity'] as num?) ?? 1;
    final hasWholesale =
        data['wholesaleEnabled'] != false &&
        wholesalePrice != null &&
        wholesalePrice > 0;
    // Fulfillment as it was when sent; older messages didn't include it.
    final deliveryLine = data['deliveryLabel']?.toString();
    final pickupLine = data['pickupLabel']?.toString();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFF4F9F1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.sell_outlined, size: 15, color: AppTheme.dark),
                const SizedBox(width: 6),
                Text(
                  isMe ? 'Order options sent' : 'Order options',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              productName,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            _priceBlock('Retail', formatPriceWithUnit(retailPrice, unit)),
            if (hasWholesale) ...[
              const SizedBox(height: 8),
              _priceBlock(
                'Wholesale',
                formatPriceWithUnit(wholesalePrice, unit),
                note: 'Minimum: ${formatStock(minimum, unit)}',
              ),
            ],
            if (deliveryLine != null && pickupLine != null) ...[
              const SizedBox(height: 8),
              _FulfillmentLines(delivery: deliveryLine, pickup: pickupLine),
            ],
            if (!isMe) ...[
              const SizedBox(height: 12),
              _chooseButton(
                'Choose Retail',
                primary: true,
                onPressed: () => _choose(productId, 'retail', retailPrice),
              ),
              if (hasWholesale) ...[
                const SizedBox(height: 6),
                _chooseButton(
                  'Choose Wholesale',
                  onPressed: () =>
                      _choose(productId, 'wholesale', wholesalePrice),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'The buyer can choose an option to order.',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceBlock(String label, String price, {String? note}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        Text(
          price,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.dark,
          ),
        ),
        if (note != null)
          Text(
            note,
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              color: Colors.grey[700],
            ),
          ),
      ],
    );
  }

  Widget _chooseButton(
    String label, {
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    );
    const padding = EdgeInsets.symmetric(vertical: 10);
    final text = Text(
      label,
      style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return SizedBox(
      width: double.infinity,
      child: primary
          ? ElevatedButton(
              onPressed: _busy ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: padding,
                shape: shape,
              ),
              child: text,
            )
          : OutlinedButton(
              onPressed: _busy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.dark,
                side: const BorderSide(color: AppTheme.dark),
                padding: padding,
                shape: shape,
              ),
              child: text,
            ),
    );
  }
}
