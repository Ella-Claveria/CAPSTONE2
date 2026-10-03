// Rating maths shared by the Farmer Profile and the Product Reviews
// screen, so a rating is worked out one way everywhere.
//
// Stored totals: `products/{id}.rating` / `.reviewCount` are recomputed by
// the recomputeProductReviewStats Cloud Function every time a review is
// created, edited or moderated, from that product's valid reviews only.
// Lists of products read those two fields instead of loading every
// review. The helpers here cover what the app itself adds up.

typedef RatingSummary = ({double average, int count});

const RatingSummary kNoRatings = (average: 0, count: 0);

/// A review counts when it hasn't been removed by moderation and carries a
/// real star rating (half stars allowed). Every review is already tied to
/// one completed order — its document id is that order's id — which is
/// also why the same order can't be counted twice.
bool isValidReview(Map<String, dynamic> review) {
  final rating = review['rating'];
  return review['moderationStatus'] != 'removed' &&
      rating is num &&
      rating >= 0.5 &&
      rating <= 5;
}

/// Average Rating = sum of the valid star ratings / number of valid reviews.
RatingSummary summarizeReviews(Iterable<Map<String, dynamic>> reviews) {
  var total = 0.0;
  var count = 0;
  final countedOrders = <String>{};
  for (final review in reviews) {
    if (!isValidReview(review)) continue;
    final orderId = (review['orderId'] ?? '').toString();
    if (orderId.isNotEmpty && !countedOrders.add(orderId)) continue;
    total += (review['rating'] as num).toDouble();
    count++;
  }
  return count == 0 ? kNoRatings : (average: total / count, count: count);
}

/// A farmer's overall rating from their products' stored totals:
/// Σ(product average × product review count) / Σ(review counts) — the same
/// as averaging every individual review, so a product with ten reviews
/// weighs five times one with two.
RatingSummary combineProductRatings(Iterable<Map<String, dynamic>> products) {
  var points = 0.0;
  var count = 0;
  for (final product in products) {
    final summary = productRating(product);
    points += summary.average * summary.count;
    count += summary.count;
  }
  return count == 0 ? kNoRatings : (average: points / count, count: count);
}

/// One product's stored rating total ([kNoRatings] if it has no reviews).
RatingSummary productRating(Map<String, dynamic> product) {
  final rating = (product['rating'] as num?)?.toDouble() ?? 0;
  final count = (product['reviewCount'] as num?)?.toInt() ?? 0;
  if (count <= 0 || rating < 0.5 || rating > 5) return kNoRatings;
  return (average: rating, count: count);
}

/// "4.6" — always one decimal place.
String formatRating(double average) => average.toStringAsFixed(1);

/// "1 review" / "18 reviews".
String reviewCountLabel(int count) =>
    '$count ${count == 1 ? 'review' : 'reviews'}';
