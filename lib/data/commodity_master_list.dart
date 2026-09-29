/// The official AgriTrade+ Commodity Master List — the commodities the
/// agricultural client has approved/supported. The AI-Assisted Price
/// Recommendation (see PriceRecommendationService) only ever runs for a
/// commodity on this list; everything else gets an explicit "not
/// supported" message instead of a guessed number.
///
/// This is NOT a marketplace-wide restriction — a farmer can still list
/// any product under Add Product's free-text title and existing category
/// picker exactly as before. This list only gates the price-suggestion
/// feature, via the separate "Commodity" selector on that screen.
const Map<String, List<String>> kCommodityMasterList = {
  'Grains': ['Rice', 'Corn'],
  'Root Crops': ['Ube', 'Sweet Potato', 'Cassava'],
  'Vegetables': [
    'Eggplant', 'Okra', 'Sitaw', 'Ampalaya', 'Squash', 'Radish', 'Malunggay',
  ],
  'Spices': ['Ginger', 'Turmeric'],
  'Fruits': ['Banana', 'Coconut'],
  'Livestock': ['Swine', 'Chicken', 'Cattle'],
  'Fisheries': ['Tilapia', 'Catfish'],
};

/// Every supported commodity, flattened, in master-list order.
final List<String> kSupportedCommodities =
    kCommodityMasterList.values.expand((names) => names).toList(growable: false);

/// The category a supported commodity belongs to, or null if [commodity]
/// isn't on the master list.
String? categoryOfCommodity(String commodity) {
  final target = commodity.trim().toLowerCase();
  for (final entry in kCommodityMasterList.entries) {
    if (entry.value.any((c) => c.toLowerCase() == target)) return entry.key;
  }
  return null;
}

/// The supported commodity [text] most likely refers to — an exact name
/// match first, then either string containing the other (so "Native
/// Chicken" or "Fresh Ginger Root" still resolves to "Chicken"/"Ginger") —
/// or null if [text] doesn't resemble any of the approved commodities.
/// This is the fallback path when a farmer hasn't picked one from the
/// Commodity dropdown explicitly; the dropdown's own value always wins
/// when set (see add_product_screen.dart).
String? matchSupportedCommodity(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final commodity in kSupportedCommodities) {
    if (commodity.toLowerCase() == t) return commodity;
  }
  for (final commodity in kSupportedCommodities) {
    final c = commodity.toLowerCase();
    if (t.contains(c) || c.contains(t)) return commodity;
  }
  return null;
}

/// The unit each supported commodity is measured/sold in. This is the
/// single source of truth for "Unit of Measurement" across Add/Edit
/// Product, the marketplace, product detail, orders, inventory, Current
/// Market Average, and Admin Reference Price — nothing else should hardcode
/// "/kg" or "kilo" again. Weight-based commodities use 'kg' (decimals
/// allowed); count-based ones use 'piece' or 'head' (whole numbers only —
/// see isCountBasedUnit); live animals commonly traded by weight use 'kg
/// liveweight'. Not exhaustive of every real-world convention — this
/// reflects the agricultural office's approved scope, and can be revised
/// here in one place if that scope's units change.
const Map<String, String> kCommodityUnits = {
  'Rice': 'kg',
  'Corn': 'kg',
  'Ube': 'kg',
  'Sweet Potato': 'kg',
  'Cassava': 'kg',
  'Eggplant': 'kg',
  'Okra': 'kg',
  'Sitaw': 'kg',
  'Ampalaya': 'kg',
  'Squash': 'kg',
  'Radish': 'kg',
  'Malunggay': 'kg',
  'Ginger': 'kg',
  'Turmeric': 'kg',
  'Banana': 'kg',
  'Coconut': 'piece',
  'Swine': 'kg liveweight',
  'Chicken': 'kg liveweight',
  'Cattle': 'head',
  'Tilapia': 'kg',
  'Catfish': 'kg',
};

/// The default unit used whenever a commodity has no configured unit (or
/// isn't recognized at all) — the safe fallback for legacy listings created
/// before this field existed.
const String kDefaultUnit = 'kg';

/// The configured unit for a supported [commodity] name — falls back to
/// [kDefaultUnit] for anything not on the master list, rather than
/// throwing, so callers never need a null check.
String unitForCommodity(String commodity) {
  final matched = kCommodityMasterList.values.expand((v) => v).contains(commodity)
      ? commodity
      : matchSupportedCommodity(commodity);
  if (matched == null) return kDefaultUnit;
  return kCommodityUnits[matched] ?? kDefaultUnit;
}

/// Same as [unitForCommodity], but for callers that only have a product's
/// free-text display name (e.g. a chat message, an order's productName) —
/// fuzzy-matches it against the master list first. Always returns a usable
/// unit, defaulting to [kDefaultUnit] for anything unrecognized.
String unitForProductName(String name) => unitForCommodity(name);

/// Count-based units (whole animals/pieces) must use whole-number
/// quantities; weight-based units ('kg', 'kg liveweight') allow decimals.
bool isCountBasedUnit(String unit) {
  final u = unit.trim().toLowerCase();
  return u == 'piece' || u == 'head';
}
