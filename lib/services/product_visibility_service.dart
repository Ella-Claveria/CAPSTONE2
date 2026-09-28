/// Ranks marketplace listings by a transparent blend of three signals —
/// consistent with the rest of the app's statistical, no-training-required
/// analytics style (see MarketTrendService, PriceRecommendationService):
///
///   - Demand: completed-order count for that specific product.
///   - Seller credibility: the seller's average rating across all their
///     reviewed products (weighted by review count), plus a fixed bonus
///     for verified farmers.
///   - Interaction: the product's own view count.
///
/// Each raw signal is min-max normalized across the current product set
/// before blending, so no single signal with a much larger raw range
/// (e.g. view counts vs. a 0-5 rating) silently dominates the others.
class ProductVisibilityService {
  static const double _wDemand = 0.45;
  static const double _wCredibility = 0.35;
  static const double _wInteraction = 0.20;

  // A flat bonus folded into a verified farmer's average rating before
  // normalizing — gives verified sellers a modest edge even before their
  // first review comes in, without letting it overwhelm real ratings.
  static const double _verifiedBonus = 1.0;

  static Map<String, double> _normalize(Map<String, double> raw) {
    if (raw.isEmpty) return {};
    final min = raw.values.reduce((a, b) => a < b ? a : b);
    final max = raw.values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    if (range <= 0) return {for (final k in raw.keys) k: 0.0};
    return {for (final e in raw.entries) e.key: (e.value - min) / range};
  }

  /// Returns a visibility score per product id — higher means more
  /// visible/prioritized. [products] are raw product doc data keyed by
  /// their own document id (not QueryDocumentSnapshot, so this stays pure
  /// and easy to unit test, same pattern as MarketTrendService).
  static Map<String, double> scoreProducts({
    required Map<String, Map<String, dynamic>> products,
    required Map<String, int> completedOrderCountByProductId,
    required Map<String, bool> verifiedByFarmerId,
  }) {
    if (products.isEmpty) return {};

    // ---- seller credibility: review-weighted average across the
    // seller's own products, not just this one listing ----
    final ratingWeightedSumByFarmer = <String, double>{};
    final ratingWeightByFarmer = <String, int>{};
    for (final data in products.values) {
      final farmerId = (data['farmerId'] ?? '').toString();
      if (farmerId.isEmpty) continue;
      final reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
      if (reviewCount <= 0) continue;
      final rating = (data['rating'] as num?)?.toDouble() ?? 0;
      ratingWeightedSumByFarmer[farmerId] = (ratingWeightedSumByFarmer[farmerId] ?? 0) + rating * reviewCount;
      ratingWeightByFarmer[farmerId] = (ratingWeightByFarmer[farmerId] ?? 0) + reviewCount;
    }

    final demandRaw = <String, double>{};
    final credibilityRaw = <String, double>{};
    final interactionRaw = <String, double>{};

    for (final entry in products.entries) {
      final id = entry.key;
      final data = entry.value;
      final farmerId = (data['farmerId'] ?? '').toString();

      demandRaw[id] = (completedOrderCountByProductId[id] ?? 0).toDouble();

      final weight = ratingWeightByFarmer[farmerId] ?? 0;
      final avgRating = weight > 0 ? (ratingWeightedSumByFarmer[farmerId]! / weight) : 0.0;
      final verified = verifiedByFarmerId[farmerId] ?? false;
      credibilityRaw[id] = avgRating + (verified ? _verifiedBonus : 0.0);

      interactionRaw[id] = ((data['viewCount'] as num?) ?? 0).toDouble();
    }

    final demand = _normalize(demandRaw);
    final credibility = _normalize(credibilityRaw);
    final interaction = _normalize(interactionRaw);

    return {
      for (final id in products.keys)
        id: _wDemand * (demand[id] ?? 0) +
            _wCredibility * (credibility[id] ?? 0) +
            _wInteraction * (interaction[id] ?? 0),
    };
  }
}
