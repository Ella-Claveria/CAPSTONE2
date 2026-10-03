import 'package:agritrade/services/review_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _review(num rating, String orderId, {String? status}) => {
  'rating': rating,
  'orderId': orderId,
  'moderationStatus': ?status,
};

void main() {
  test('average = sum of valid ratings / number of valid reviews', () {
    final summary = summarizeReviews([
      _review(5, 'o1'),
      _review(5, 'o2'),
      _review(4, 'o3'),
      _review(4, 'o4'),
      _review(5, 'o5'),
    ]);
    expect(summary.count, 5);
    expect(formatRating(summary.average), '4.6');
    expect(reviewCountLabel(summary.count), '5 reviews');
  });

  test('removed, invalid and duplicate-order reviews are not counted', () {
    final summary = summarizeReviews([
      _review(4.5, 'o1'),
      _review(1, 'o2', status: 'removed'),
      _review(0, 'o3'),
      _review(9, 'o4'),
      {'rating': 'five', 'orderId': 'o5'},
      _review(2, 'o1'), // same completed order again
    ]);
    expect(summary.count, 1);
    expect(summary.average, 4.5);
  });

  test('no reviews gives no rating, not 0.0', () {
    expect(summarizeReviews(const []), kNoRatings);
    expect(combineProductRatings(const []), kNoRatings);
    expect(productRating({'rating': 0.0, 'reviewCount': 0}), kNoRatings);
    expect(reviewCountLabel(1), '1 review');
  });

  test('farmer overall rating weights products by their review counts', () {
    final overall = combineProductRatings([
      {'rating': 4.8, 'reviewCount': 10},
      {'rating': 3.0, 'reviewCount': 2},
      {'rating': 0.0, 'reviewCount': 0}, // unreviewed product
    ]);
    expect(overall.count, 12);
    // (4.8 × 10 + 3.0 × 2) / 12 = 4.5 — not (4.8 + 3.0) / 2 = 3.9.
    expect(formatRating(overall.average), '4.5');
  });
}
