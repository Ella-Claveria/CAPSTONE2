import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The AgriTrade+ commodity list — the products farmers may post, their
/// category and their unit of measurement.
///
/// One source of truth: the Admin-managed `market_prices` collection (Admin
/// Portal → Commodity Price Management → Add Commodity). Every commodity
/// there with a category shows up, under that category, in the Farmer
/// Supported Products screen and in Add Product's Product Name suggestions;
/// disabling it there (`isActive: false`) takes it out of both, without
/// touching listings that already use it. [CommodityRegistry] keeps a live
/// copy so the rest of the app can keep asking synchronously.
///
/// Deleting a commodity there removes it here as well.
///
/// [_defaultCommodities] is only the starting set: the commodities agreed
/// with the agricultural office, used until the Admin's list has loaded, or
/// while the Admin has no commodity on record at all. It also lends its
/// category and unit to an Admin record of the same name that lacks one.

class Commodity {
  final String name;
  final String category;
  final String unit;

  /// Disabled commodities can't be chosen for a new product, but are still
  /// recognized (category, unit) for listings that already use them.
  final bool isActive;

  const Commodity(this.name, this.category, this.unit, {this.isActive = true});
}

const List<Commodity> _defaultCommodities = [
  Commodity('Rice', 'Grains', 'kg'),
  Commodity('Corn', 'Grains', 'kg'),
  Commodity('Ube', 'Root Crops', 'kg'),
  Commodity('Sweet Potato', 'Root Crops', 'kg'),
  Commodity('Cassava', 'Root Crops', 'kg'),
  Commodity('Eggplant', 'Vegetables', 'kg'),
  Commodity('Okra', 'Vegetables', 'kg'),
  Commodity('Sitaw', 'Vegetables', 'kg'),
  Commodity('Ampalaya', 'Vegetables', 'kg'),
  Commodity('Squash', 'Vegetables', 'kg'),
  Commodity('Radish', 'Vegetables', 'kg'),
  Commodity('Malunggay', 'Vegetables', 'kg'),
  Commodity('Ginger', 'Spices', 'kg'),
  Commodity('Turmeric', 'Spices', 'kg'),
  Commodity('Banana', 'Fruits', 'kg'),
  Commodity('Coconut', 'Fruits', 'piece'),
  Commodity('Swine', 'Livestock', 'kg liveweight'),
  Commodity('Chicken', 'Livestock', 'kg liveweight'),
  Commodity('Cattle', 'Livestock', 'head'),
];

/// The default unit used whenever a commodity has no configured unit (or
/// isn't recognized at all) — the safe fallback for legacy listings created
/// before this field existed.
const String kDefaultUnit = 'kg';

/// The units the app knows how to handle (whole numbers vs decimals, stock
/// and price labels). An Admin record with any other unit text falls back
/// to the commodity's default unit.
const List<String> kCommodityUnitOptions = [
  'kg',
  'piece',
  'head',
  'kg liveweight',
];

/// Live copy of the Admin-managed commodity list.
class CommodityRegistry extends ChangeNotifier {
  CommodityRegistry._();
  static final CommodityRegistry instance = CommodityRegistry._();

  List<Commodity> _all = _defaultCommodities;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  /// Starts following the Admin's list. Call once, after Firebase is
  /// initialized; safe to call again.
  void start() {
    _sub ??= FirebaseFirestore.instance
        .collection('market_prices')
        .snapshots()
        .listen(
          (snap) => applyAdminRecords(snap.docs.map((d) => d.data())),
          // Offline / not readable: keep what we have.
          onError: (_) {},
        );
  }

  /// Rebuilds the list from the Admin's `market_prices` records. Once the
  /// Admin has any commodity on record, that list is the whole list: one
  /// the Admin deletes is gone here too, default or not.
  void applyAdminRecords(Iterable<Map<String, dynamic>> records) {
    // The defaults only lend a category or unit to an Admin record of the
    // same name that lacks one; they are not added to the list themselves.
    final defaults = <String, Commodity>{
      for (final c in _defaultCommodities) c.name.toLowerCase(): c,
    };
    final merged = <String, Commodity>{};
    for (final data in records) {
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final fallback = defaults[key];
      final category = (data['category'] ?? '').toString().trim();
      // A price record with no category isn't a postable commodity yet.
      if (category.isEmpty && fallback == null) continue;
      final unit = (data['unit'] ?? '').toString().trim().toLowerCase();
      merged[key] = Commodity(
        name,
        category.isEmpty ? fallback!.category : category,
        kCommodityUnitOptions.contains(unit)
            ? unit
            : (fallback?.unit ?? kDefaultUnit),
        isActive: data['isActive'] != false,
      );
    }
    // Nothing from the Admin yet (a new installation): the starting set.
    _all = merged.isEmpty
        ? _defaultCommodities
        : merged.values.toList(growable: false);
    notifyListeners();
  }

  /// Every known commodity, active or not.
  List<Commodity> get all => _all;

  /// The commodities a farmer can choose for a new product.
  List<String> get activeNames => [
    for (final c in _all)
      if (c.isActive) c.name,
  ];

  /// Active commodities grouped under their category, in list order — new
  /// categories appear on their own as the Admin adds commodities to them.
  Map<String, List<String>> get activeByCategory {
    final grouped = <String, List<String>>{};
    for (final c in _all) {
      if (c.isActive) grouped.putIfAbsent(c.category, () => []).add(c.name);
    }
    return grouped;
  }

  /// Every category that has a commodity (active or not), so buyers can
  /// still browse listings of a commodity that was later disabled.
  List<String> get categories => {for (final c in _all) c.category}.toList();

  Commodity? find(String name) {
    final target = name.trim().toLowerCase();
    for (final c in _all) {
      if (c.name.toLowerCase() == target) return c;
    }
    return null;
  }
}

/// The category a commodity belongs to, or null if [commodity] isn't on
/// the list.
String? categoryOfCommodity(String commodity) =>
    CommodityRegistry.instance.find(commodity)?.category;

/// The commodity [text] most likely refers to — an exact name match first,
/// then either string containing the other (so "Native Chicken" or "Fresh
/// Ginger Root" still resolves to "Chicken"/"Ginger") — or null if [text]
/// doesn't resemble any commodity on the list.
///
/// [activeOnly] limits it to commodities a farmer may choose for a new
/// product. Everything that only needs to recognize a name (units, prices,
/// reports, existing listings) leaves it off, so a commodity the Admin has
/// disabled is still understood.
String? matchSupportedCommodity(String text, {bool activeOnly = false}) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  final names = [
    for (final c in CommodityRegistry.instance.all)
      if (!activeOnly || c.isActive) c.name,
  ];
  for (final commodity in names) {
    if (commodity.toLowerCase() == t) return commodity;
  }
  for (final commodity in names) {
    final c = commodity.toLowerCase();
    if (t.contains(c) || c.contains(t)) return commodity;
  }
  return null;
}

/// The configured unit for a [commodity] name — the single source of truth
/// for "Unit of Measurement" across Add/Edit Product, the marketplace,
/// product detail, orders, inventory, Current Market Average, and Admin
/// Reference Price. Falls back to [kDefaultUnit] for anything not on the
/// list, rather than throwing, so callers never need a null check.
String unitForCommodity(String commodity) {
  final registry = CommodityRegistry.instance;
  final found =
      registry.find(commodity) ??
      registry.find(matchSupportedCommodity(commodity) ?? '');
  return found?.unit ?? kDefaultUnit;
}

/// Same as [unitForCommodity], but for callers that only have a product's
/// free-text display name (e.g. a chat message, an order's productName) —
/// fuzzy-matches it against the list first. Always returns a usable unit,
/// defaulting to [kDefaultUnit] for anything unrecognized.
String unitForProductName(String name) => unitForCommodity(name);

/// Count-based units (whole animals/pieces) must use whole-number
/// quantities; weight-based units ('kg', 'kg liveweight') allow decimals.
bool isCountBasedUnit(String unit) {
  final u = unit.trim().toLowerCase();
  return u == 'piece' || u == 'head';
}

/// How a livestock listing is sold, chosen in Add Product for every
/// commodity the Admin files under Livestock: alive, in the commodity's own
/// unit (kg liveweight or head), or slaughtered, always per kg. Saved on
/// the listing and on its orders as 'sellingOption'.
enum SellingOption {
  live('live', 'Live'),
  slaughtered('slaughtered', 'Slaughtered');

  const SellingOption(this.value, this.label);

  /// What is stored in 'sellingOption'.
  final String value;
  final String label;
}

/// The unit of a slaughtered livestock listing.
const String kSlaughteredUnit = 'kg';

/// True for the Livestock category, whatever the Admin's capitals.
bool isLivestockCategory(String? category) =>
    (category ?? '').trim().toLowerCase() == 'livestock';

/// The selling option saved on a listing or an order, or null when it has
/// none (not livestock, or a listing saved before the option existed —
/// sold live).
SellingOption? sellingOptionOf(Map<String, dynamic>? data) =>
    switch ((data?['sellingOption'] ?? '').toString()) {
      'live' => SellingOption.live,
      'slaughtered' => SellingOption.slaughtered,
      _ => null,
    };

/// True when a listing or an order is for slaughtered livestock.
bool isSlaughtered(Map<String, dynamic>? data) =>
    sellingOptionOf(data) == SellingOption.slaughtered;

/// The unit a listing of [commodity] is sold in: per kg when slaughtered,
/// otherwise the commodity's own unit.
String unitForListing(String commodity, SellingOption? option) =>
    option == SellingOption.slaughtered
    ? kSlaughteredUnit
    : unitForCommodity(commodity);

/// [name] with the selling option after it — "Swine (Live)",
/// "Cattle (Slaughtered)" — or [name] alone when there is none.
String withSellingOption(String name, Map<String, dynamic>? data) {
  final option = sellingOptionOf(data);
  return option == null ? name : '$name (${option.label})';
}
