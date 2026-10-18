import 'package:cloud_firestore/cloud_firestore.dart';

import 'product_recommendation_service.dart';

/// What a buyer's Recommended Products were chosen by.
enum RecommendationBasis {
  /// Their own orders, likes and searches.
  personal,

  /// What buyers in their town buy most (they have no history yet).
  area,

  /// The newest listings (no history, and no sales in their town yet).
  newest,
}

/// "Recommended Products" in a buyer's Search, in three steps:
///
/// 1. **Their own history**, when they have any:
///      40%  category — the categories they buy most, and those of the
///           products they liked (a purchase counts more than a like)
///      25%  searches — the listing matches something they searched lately
///           (newer searches count more)
///      15%  repeat — the same product (commodity) they bought before
///      20%  marketplace popularity — sales, rating and reviews
/// 2. Otherwise, **what buyers in their town buy most** (completed sales in
///    market_sales with the same buyerArea): the same product first, then
///    the same category.
/// 3. Otherwise, **the newest listings** farmers posted.
///
/// Only active, in-stock listings are recommended.
class PersonalRecommendations {
  const PersonalRecommendations._();

  static const double weightCategory = 0.40;
  static const double weightSearch = 0.25;
  static const double weightRepeat = 0.15;
  static const double weightPopular = 0.20;

  // A like says less about what someone buys than a purchase does.
  static const double _likeWeight = 0.6;

  /// Product ids, best first, and what they were chosen by.
  ///
  /// [products]: listing data by id. [orders]: the buyer's own orders
  /// (rejected and cancelled ones are not counted). [likedIds]: products
  /// they liked. [searches]: their recent search terms, newest first.
  /// [areaSales]: completed sales to buyers in their town.
  static ({List<String> ids, RecommendationBasis basis}) recommend({
    required Map<String, Map<String, dynamic>> products,
    List<Map<String, dynamic>> orders = const [],
    Iterable<String> likedIds = const [],
    List<String> searches = const [],
    List<Map<String, dynamic>> areaSales = const [],
  }) {
    final candidates = {
      for (final e in products.entries)
        if (ProductRecommendationService.isRecommendable(e.value))
          e.key: e.value,
    };
    if (candidates.isEmpty) {
      return (ids: const [], basis: RecommendationBasis.newest);
    }

    // ---- 1. Their own history ----
    final categoryWeight = <String, double>{};
    final boughtCommodities = <String>{};
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status == 'rejected' || status == 'cancelled') continue;
      final category = _key(order['category']);
      if (category.isNotEmpty) {
        categoryWeight[category] = (categoryWeight[category] ?? 0) + 1;
      }
      final commodity = _key(order['commodity'] ?? order['productName']);
      if (commodity.isNotEmpty) boughtCommodities.add(commodity);
    }
    for (final id in likedIds) {
      final category = _key(products[id]?['category']);
      if (category.isNotEmpty) {
        categoryWeight[category] =
            (categoryWeight[category] ?? 0) + _likeWeight;
      }
    }
    final topCategory = _max(categoryWeight.values);
    final terms = [
      for (final s in searches)
        if (_key(s).length >= 2) _key(s),
    ].take(10).toList();

    final newestFirst = candidates.keys.toList()
      ..sort((a, b) => _created(candidates[b]!).compareTo(_created(candidates[a]!)));
    final newestIndex = {
      for (var i = 0; i < newestFirst.length; i++) newestFirst[i]: i,
    };
    List<String> sortedBy(Map<String, double> score) =>
        candidates.keys.toList()..sort((a, b) {
          final byScore = score[b]!.compareTo(score[a]!);
          if (byScore != 0) return byScore;
          return newestIndex[a]!.compareTo(newestIndex[b]!);
        });

    if (topCategory > 0 || terms.isNotEmpty || boughtCommodities.isNotEmpty) {
      final popular = ProductRecommendationService.scoreProducts(candidates);
      final score = <String, double>{};
      for (final e in candidates.entries) {
        final p = e.value;
        final category = _key(p['category']);
        final commodity = _key(p['commodity'] ?? p['name']);
        final text = '${_key(p['name'])} $commodity $category';
        final categoryPart = topCategory == 0
            ? 0.0
            : (categoryWeight[category] ?? 0) / topCategory;
        // The newest search that matches counts most.
        var searchPart = 0.0;
        for (var i = 0; i < terms.length; i++) {
          if (text.contains(terms[i])) {
            searchPart = 1 - i / (terms.length + 1);
            break;
          }
        }
        final repeatPart = boughtCommodities.contains(commodity) ? 1.0 : 0.0;
        score[e.key] =
            weightCategory * categoryPart +
            weightSearch * searchPart +
            weightRepeat * repeatPart +
            weightPopular * (popular[e.key] ?? 0);
      }
      return (ids: sortedBy(score), basis: RecommendationBasis.personal);
    }

    // ---- 2. What buyers in their town buy ----
    final soldByProduct = <String, double>{};
    final soldByCategory = <String, double>{};
    for (final sale in areaSales) {
      final quantity = 1.0; // each completed order counts once
      final name = _key(sale['productName']);
      final category = _key(sale['category']);
      if (name.isNotEmpty) {
        soldByProduct[name] = (soldByProduct[name] ?? 0) + quantity;
      }
      if (category.isNotEmpty) {
        soldByCategory[category] = (soldByCategory[category] ?? 0) + quantity;
      }
    }
    final topProduct = _max(soldByProduct.values);
    final topSold = _max(soldByCategory.values);
    if (topProduct > 0 || topSold > 0) {
      final score = <String, double>{
        for (final e in candidates.entries)
          e.key:
              0.7 *
                  (topProduct == 0
                      ? 0
                      : (soldByProduct[_key(e.value['commodity'] ?? e.value['name'])] ??
                                soldByProduct[_key(e.value['name'])] ??
                                0) /
                            topProduct) +
              0.3 *
                  (topSold == 0
                      ? 0
                      : (soldByCategory[_key(e.value['category'])] ?? 0) /
                            topSold),
      };
      return (ids: sortedBy(score), basis: RecommendationBasis.area);
    }

    // ---- 3. The newest listings ----
    return (ids: newestFirst, basis: RecommendationBasis.newest);
  }

  static double _max(Iterable<double> values) =>
      values.fold<double>(0, (a, b) => a > b ? a : b);

  static int _created(Map<String, dynamic> product) {
    final value = product['createdAt'];
    return value is Timestamp ? value.millisecondsSinceEpoch : 0;
  }

  static String _key(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase();
}
