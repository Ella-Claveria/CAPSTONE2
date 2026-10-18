import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/commodity_master_list.dart';
import '../services/market_price_helpers.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../theme/app_theme.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/retry_message.dart';

/// Low Stock: 20% or less of the stock the farmer last set (when posting,
/// restocking or editing the quantity — saved as the product's
/// stockBaseline) is left. Orders bring the quantity down, never the
/// baseline, so the rule fits every size of harvest: 100 kg → low at
/// 20 kg, 1,000 kg → at 200 kg, 10 head → at 2.
const double kLowStockFraction = 0.2;

/// For a listing saved before stockBaseline existed: a plain minimum per
/// unit instead.
num lowStockFallback(String unit) => switch (unit.trim().toLowerCase()) {
  'head' => 2,
  _ => 10,
};

enum StockStatus { inStock, lowStock, outOfStock }

/// The quantity at or below which [unit] stock is low, given the farmer's
/// last-set [baseline]. Whole animals or pieces round up, so 3 head is
/// low at 1.
num lowStockThreshold({num? baseline, num quantity = 0, String unit = 'kg'}) {
  if (baseline == null || baseline <= 0) return lowStockFallback(unit);
  // Never below what is in stock now: a baseline only goes up with it.
  final base = baseline < quantity ? quantity : baseline;
  final threshold = base * kLowStockFraction;
  return isCountBasedUnit(unit) ? threshold.ceil() : threshold;
}

StockStatus stockStatusOf(num quantity, {num? baseline, String unit = 'kg'}) =>
    quantity <= 0
    ? StockStatus.outOfStock
    : quantity <=
          lowStockThreshold(baseline: baseline, quantity: quantity, unit: unit)
    ? StockStatus.lowStock
    : StockStatus.inStock;

/// [stockStatusOf] for a product document.
StockStatus stockStatusOfProduct(Map<String, dynamic> product) {
  final value = product['quantity'];
  final quantity = value is num ? value : num.tryParse('${value ?? ''}') ?? 0;
  final baseline = product['stockBaseline'];
  final unit = (product['unit'] ?? '').toString().trim();
  return stockStatusOf(
    quantity,
    baseline: baseline is num ? baseline : null,
    unit: unit.isNotEmpty
        ? unit
        : unitForProductName(
            (product['commodity'] ?? product['name'] ?? '').toString(),
          ),
  );
}

/// Completed-order quantity per product id. Only completed orders count as
/// sold; pending, confirmed, shipped and rejected ones do not.
Map<String, num> soldByProduct(Iterable<Map<String, dynamic>> orders) {
  final sold = <String, num>{};
  for (final order in orders) {
    if ((order['status'] ?? '').toString().toLowerCase() != 'completed') {
      continue;
    }
    final productId = (order['productId'] ?? '').toString();
    final quantity = order['quantity'];
    if (productId.isEmpty || quantity is! num) continue;
    sold[productId] = (sold[productId] ?? 0) + quantity;
  }
  return sold;
}

/// The farmer's Basic Inventory: current stock of each active listing, with
/// low/out-of-stock monitoring and a quick stock update.
///
/// There is no separate inventory record. "Available" is the product's own
/// `quantity` field — the one Add/Edit Product writes, the marketplace
/// shows and placing an order deducts — read live, so an order or an edit
/// anywhere shows up here at once, and an update here shows up there.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ProductService _productService = ProductService();
  // Created once — never in build().
  late Stream<QuerySnapshot<Map<String, dynamic>>> _products = _productService
      .myProductsStream();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _orders =
      OrderService().farmerOrdersStream();

  // null = All.
  StockStatus? _filter;

  static num _quantityOf(Map<String, dynamic> product) {
    final value = product['quantity'];
    return value is num ? value : num.tryParse('${value ?? ''}') ?? 0;
  }

  static String _unitOf(Map<String, dynamic> product) {
    final unit = (product['unit'] ?? '').toString().trim();
    return unit.isNotEmpty
        ? unit
        : unitForProductName(
            (product['commodity'] ?? product['name'] ?? '').toString(),
          );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppTheme.dark,
        content: Text(message),
      ),
    );
  }

  Future<void> _updateStock(String id, Map<String, dynamic> product) async {
    final unit = _unitOf(product);
    final name = (product['name'] ?? 'Product').toString();
    final newQuantity = await showAgriDialog<num>(
      context: context,
      builder: (_) => _UpdateStockDialog(
        name: name,
        current: _quantityOf(product),
        unit: unit,
      ),
    );
    if (newQuantity == null || !mounted) return;
    // The same write the product list's quick stock edit uses.
    final error = await _productService.updateQuantity(id, newQuantity);
    if (!mounted) return;
    _snack(
      error ?? '$name stock updated to ${formatStock(newQuantity, unit)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: const AgriAppBar(title: 'Inventory'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _products,
        builder: (context, productSnap) {
          if (productSnap.hasError && !productSnap.hasData) {
            return RetryMessage(
              message:
                  'Could not load your inventory. Check your connection and try again.',
              onRetry: () => setState(
                () => _products = _productService.myProductsStream(),
              ),
            );
          }
          if (!productSnap.hasData) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.dark,
                ),
              ),
            );
          }
          // Archived listings are paused, not stock to monitor; they stay
          // in the farmer's product list.
          final products = productSnap.data!.docs
              .where((doc) => doc.data()['isArchived'] != true)
              .toList();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _orders,
            builder: (context, orderSnap) {
              final sold = soldByProduct(
                orderSnap.data?.docs.map((d) => d.data()) ?? const [],
              );
              return _body(products, sold);
            },
          );
        },
      ),
    );
  }

  Widget _body(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    Map<String, num> sold,
  ) {
    StockStatus statusOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
        stockStatusOfProduct(doc.data());
    int count(StockStatus status) =>
        products.where((doc) => statusOf(doc) == status).length;

    final shown =
        products
            .where((doc) => _filter == null || statusOf(doc) == _filter)
            .toList()
          // What needs attention first, then by name.
          ..sort((a, b) {
            final byStatus = statusOf(b).index.compareTo(statusOf(a).index);
            if (byStatus != 0) return byStatus;
            return (a.data()['name'] ?? '').toString().toLowerCase().compareTo(
              (b.data()['name'] ?? '').toString().toLowerCase(),
            );
          });

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _stat('${products.length}', 'Active Products', AppTheme.dark),
              _statDivider(),
              _stat(
                '${count(StockStatus.lowStock)}',
                'Low Stock',
                Colors.orange.shade800,
              ),
              _statDivider(),
              _stat(
                '${count(StockStatus.outOfStock)}',
                'Out of Stock',
                Colors.red.shade700,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _filterChip('All', null),
            const SizedBox(width: 8),
            _filterChip('Low Stock', StockStatus.lowStock),
            const SizedBox(width: 8),
            _filterChip('Out of Stock', StockStatus.outOfStock),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Text(
              switch (_filter) {
                null =>
                  'No products yet. Products you add will appear here with their stock.',
                StockStatus.lowStock => 'No products are running low.',
                _ => 'No products are out of stock.',
              },
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          )
        else
          for (final doc in shown)
            _productRow(doc.id, doc.data(), sold[doc.id]),
      ],
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: Colors.grey.shade200);

  Widget _filterChip(String label, StockStatus? value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.dark : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? AppTheme.dark : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _productRow(String id, Map<String, dynamic> product, num? sold) {
    final name = (product['name'] ?? 'Product').toString();
    final unit = _unitOf(product);
    final quantity = _quantityOf(product);
    final status = stockStatusOfProduct(product);
    final imageUrl = (product['imageUrl'] ?? '').toString();
    final (String statusLabel, Color statusColor) = switch (status) {
      StockStatus.inStock => ('IN STOCK', AppTheme.dark),
      StockStatus.lowStock => ('LOW STOCK', Colors.orange.shade800),
      StockStatus.outOfStock => ('OUT OF STOCK', Colors.red.shade700),
    };
    final fallback = Container(
      color: AppTheme.accent,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.dark,
        ),
      ),
    );
    final restock = status == StockStatus.outOfStock;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 50,
              height: 50,
              child: imageUrl.isEmpty
                  ? fallback
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  withSellingOption(name, product),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Available: ${formatStock(quantity, unit)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                if (sold != null && sold > 0)
                  Text(
                    'Sold: ${formatStock(sold, unit)}',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.montserrat(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _updateStock(id, product),
            style: TextButton.styleFrom(
              foregroundColor: restock ? Colors.white : AppTheme.dark,
              backgroundColor: restock ? AppTheme.dark : Colors.white,
              side: restock
                  ? BorderSide.none
                  : BorderSide(color: Colors.grey.shade400),
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.montserrat(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(restock ? 'Restock' : 'Update Stock'),
          ),
        ],
      ),
    );
  }
}

/// Asks for a product's new available stock. Pops with the validated
/// amount, or nothing on Cancel. Same rules as Add/Edit Product: never
/// negative; whole numbers for count-based units (piece, head), decimals
/// allowed for weight-based ones.
class _UpdateStockDialog extends StatefulWidget {
  final String name;
  final num current;
  final String unit;

  const _UpdateStockDialog({
    required this.name,
    required this.current,
    required this.unit,
  });

  @override
  State<_UpdateStockDialog> createState() => _UpdateStockDialogState();
}

class _UpdateStockDialogState extends State<_UpdateStockDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  bool get _countBased => isCountBasedUnit(widget.unit);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = num.tryParse(_controller.text.trim());
    final String? error;
    if (parsed == null) {
      error = 'Enter the new stock amount.';
    } else if (parsed < 0) {
      error = 'Stock cannot be negative.';
    } else if (_countBased && parsed != parsed.roundToDouble()) {
      error = 'Stock for ${widget.unit} must be a whole number.';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<num>(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AgriDialog(
      title: Text('Update ${widget.name} Stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Stock: ${formatStock(widget.current, widget.unit)}'),
          const SizedBox(height: 14),
          Text(
            'New Available Stock',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !_countBased,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(_countBased ? r'[0-9]' : r'[0-9.]'),
              ),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              suffixText: widget.unit,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AgriDialogButton(
          label: 'Update Stock',
          kind: AgriButtonKind.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
