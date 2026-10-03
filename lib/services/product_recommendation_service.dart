import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Ranks listings for Recommended Products from real marketplace
/// performance — nothing here is random, hardcoded or personal:
///
///   50%  purchase popularity — the product's completed orders
///   30%  average rating
///   20%  review confidence — how many reviews that rating rests on
///
/// All three come from fields Cloud Functions keep on the product itself
/// (see functions/index.js), which a farmer cannot write:
///   completedOrderCount  orders for this product whose status is
///                        'completed' — pending, rejected and cancelled
///                        orders are never counted
///   rating, reviewCount  from reviews tied to the buyer's own completed
///                        order, excluding any removed by moderation
///
/// Each signal is normalized to 0..1 before the weights are applied, so
/// none dominates just because its raw numbers are bigger:
///   - order and review counts on a log scale against the busiest product
///     (200 orders vs 20 is an edge, not a 10x lead);
///   - the rating as a Bayesian average — pulled towards the marketplace's
///     overall average until enough reviews back it up — so a lone 5.0
///     from one review does not outrank a 4.7 from thirty.
class ProductRecommendationService {
  static const double weightSales = 0.5;
  static const double weightRating = 0.3;
  static const double weightReviews = 0.2;

  // How many "average" reviews a product's own reviews are weighed against.
  static const double _priorReviews = 5;
  // Used as the marketplace average when no product has a review yet.
  static const double _defaultAverageRating = 3.5;

  static int completedOrders(Map<String, dynamic> product) =>
      math.max(0, (product['completedOrderCount'] as num?)?.toInt() ?? 0);

  static int _reviewCount(Map<String, dynamic> product) =>
      math.max(0, (product['reviewCount'] as num?)?.toInt() ?? 0);

  static double _rating(Map<String, dynamic> product) =>
      ((product['rating'] as num?)?.toDouble() ?? 0).clamp(0, 5).toDouble();

  /// Whether a listing may be recommended at all: on the marketplace and
  /// actually available to buy.
  static bool isRecommendable(Map<String, dynamic> product) =>
      product['isArchived'] != true &&
      product['isSuspended'] != true &&
      ((product['quantity'] as num?) ?? 0) > 0;

  /// Score (0..1) per product id. [products] is raw product data keyed by
  /// document id.
  static Map<String, double> scoreProducts(
    Map<String, Map<String, dynamic>> products,
  ) {
    if (products.isEmpty) return {};

    var maxOrders = 0;
    var maxReviews = 0;
    var ratingSum = 0.0;
    var ratingWeight = 0;
    for (final product in products.values) {
      maxOrders = math.max(maxOrders, completedOrders(product));
      final reviews = _reviewCount(product);
      maxReviews = math.max(maxReviews, reviews);
      ratingSum += _rating(product) * reviews;
      ratingWeight += reviews;
    }
    final marketAverage = ratingWeight == 0
        ? _defaultAverageRating
        : ratingSum / ratingWeight;

    double logShare(int value, int max) =>
        max <= 0 ? 0 : math.log(1 + value) / math.log(1 + max);

    return {
      for (final entry in products.entries)
        entry.key: () {
          final product = entry.value;
          final reviews = _reviewCount(product);
          // No reviews = no rating signal at all (not an assumed average).
          final rating = reviews == 0
              ? 0.0
              : ((reviews * _rating(product) + _priorReviews * marketAverage) /
                        (reviews + _priorReviews)) /
                    5;
          return weightSales * logShare(completedOrders(product), maxOrders) +
              weightRating * rating +
              weightReviews * logShare(reviews, maxReviews);
        }(),
    };
  }

  /// Product ids, best first. Listings with no sales or reviews yet all
  /// score zero; they (and any other tie) fall back to real activity —
  /// most viewed first, then most recently posted.
  static List<String> rank(Map<String, Map<String, dynamic>> products) {
    final eligible = {
      for (final entry in products.entries)
        if (isRecommendable(entry.value)) entry.key: entry.value,
    };
    final scores = scoreProducts(eligible);

    int views(String id) => (eligible[id]!['viewCount'] as num?)?.toInt() ?? 0;
    int posted(String id) {
      final createdAt = eligible[id]!['createdAt'];
      return createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : 0;
    }

    return eligible.keys.toList()..sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      if (byScore != 0) return byScore;
      final byViews = views(b).compareTo(views(a));
      if (byViews != 0) return byViews;
      final byDate = posted(b).compareTo(posted(a));
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }
}
