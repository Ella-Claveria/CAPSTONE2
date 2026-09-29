import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';

/// Shared formatting + aggregation helpers so every screen — admin Price
/// Management, the marketplace, product detail, orders, inventory, and
/// analytics — displays price/stock/unit the same way instead of each
/// hardcoding its own "/kg" or "kilo" string.

final NumberFormat _pesoFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

String formatPeso(num value) => _pesoFormat.format(value);

/// "₱72.50/kg", "₱210.00/kg liveweight", "₱35,000.00/head" — a price
/// combined with its commodity's configured unit. Falls back to
/// [kDefaultUnit] only when [unit] is genuinely unset (older records
/// predating the Unit field), never silently assuming every commodity is
/// sold per kilo.
String formatPriceWithUnit(num price, String? unit) {
  final label = (unit == null || unit.trim().isEmpty) ? kDefaultUnit : unit.trim();
  return '${formatPeso(price)}/$label';
}

/// "Price per kg", "Price per piece", "Price per head" — always the
/// singular form of the unit, for field labels (never pluralized, unlike
/// [formatStock]).
String pricePerUnitLabel(String? unit) {
  final label = (unit == null || unit.trim().isEmpty) ? kDefaultUnit : unit.trim();
  return 'Price per $label';
}

/// "50 kg", "100 pieces", "3 heads", "120 kg liveweight" — a stock/order
/// quantity combined with its unit, pluralized for count-based units when
/// the quantity isn't exactly 1 (weight-based units like "kg"/"kg
/// liveweight" are never pluralized).
String formatStock(num quantity, String? unit) {
  final label = (unit == null || unit.trim().isEmpty) ? kDefaultUnit : unit.trim();
  final qtyText = quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toStringAsFixed(2);
  if (isCountBasedUnit(label) && quantity != 1) {
    return '$qtyText ${label}s';
  }
  return '$qtyText $label';
}

String timeAgo(Timestamp? ts) {
  if (ts == null) return 'just now';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('MMM d, y').format(ts.toDate());
}

/// Average asking price of ACTIVE Farmer listings whose commodity/name/
/// category matches [commodityKey] (case-insensitive) — never the admin's
/// imported/entered reference price, which is a separate, independent
/// figure (see market_prices.baselinePrice). "Active" excludes archived,
/// suspended, and sold-out (quantity <= 0) listings, since an asking price
/// that isn't actually for sale right now shouldn't count toward what the
/// market is currently charging. Returns null when nothing matches, so
/// callers can show an explicit "No active listings" state instead of a
/// fake 0 or a silent fallback to the reference price.
double? computeLiveAverage(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  String commodityKey, {
  String pricingType = 'retail',
}) {
  final key = commodityKey.trim().toLowerCase();
  if (key.isEmpty) return null;

  final matches = <double>[];
  final expectedUnit = unitForCommodity(matchSupportedCommodity(commodityKey) ?? commodityKey);

  for (final doc in products) {
    final data = doc.data();
    if (data['isArchived'] == true || data['isSuspended'] == true) continue;

    final rawQuantity = data['quantity'];
    final quantity = rawQuantity is num
        ? rawQuantity.toDouble()
        : num.tryParse(rawQuantity?.toString() ?? '')?.toDouble();
    if (quantity == null || quantity <= 0) continue;

    final commodity = (data['commodity'] ?? '').toString().toLowerCase();
    final name = (data['name'] ?? '').toString().toLowerCase();
    final category = (data['category'] ?? '').toString().toLowerCase();
    if (commodity != key && !name.contains(key) && !category.contains(key)) continue;

    final unit = (data['unit'] ?? unitForProductName(data['name']?.toString() ?? '')).toString();
    if (expectedUnit.isNotEmpty && unit.isNotEmpty && unit != expectedUnit) continue;

    dynamic raw;
    if (pricingType == 'wholesale') {
      final explicitEnabled = data['wholesaleEnabled'];
      final wholesalePrice = data['wholesalePrice'];
      final enabled = explicitEnabled == true ||
          (explicitEnabled == null && wholesalePrice is num && wholesalePrice > 0);
      if (!enabled) continue;
      raw = wholesalePrice;
    } else {
      raw = data['retailPrice'] ?? data['price'];
    }

    final price = raw is num
        ? raw.toDouble()
        : num.tryParse(raw?.toString() ?? '')?.toDouble();
    if (price != null && price > 0) matches.add(price);
  }

  if (matches.isEmpty) return null;
  return matches.reduce((a, b) => a + b) / matches.length;
}

double? computeWholesaleLiveAverage(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  String commodityKey,
) =>
    computeLiveAverage(products, commodityKey, pricingType: 'wholesale');
