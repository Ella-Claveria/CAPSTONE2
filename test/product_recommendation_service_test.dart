import 'package:agritrade/services/product_recommendation_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product({
  int orders = 0,
  double rating = 0,
  int reviews = 0,
  num quantity = 10,
  int views = 0,
  DateTime? created,
  bool archived = false,
  bool suspended = false,
}) => {
  'completedOrderCount': orders,
  'rating': rating,
  'reviewCount': reviews,
  'quantity': quantity,
  'viewCount': views,
  if (created != null) 'createdAt': Timestamp.fromDate(created),
  'isArchived': archived,
  'isSuspended': suspended,
};

void main() {
  test('weights add up to 100%, with completed sales the strongest', () {
    expect(
      ProductRecommendationService.weightSales +
          ProductRecommendationService.weightRating +
          ProductRecommendationService.weightReviews,
      closeTo(1, 1e-9),
    );
    expect(
      ProductRecommendationService.weightSales,
      greaterThan(ProductRecommendationService.weightRating),
    );
    expect(
      ProductRecommendationService.weightRating,
      greaterThan(ProductRecommendationService.weightReviews),
    );
  });

  test('a lone 5.0 does not outrank strong sales with many good reviews', () {
    final ranked = ProductRecommendationService.rank({
      'one_perfect_review': product(orders: 1, rating: 5.0, reviews: 1),
      'proven_seller': product(orders: 40, rating: 4.6, reviews: 30),
    });
    expect(ranked.first, 'proven_seller');
  });

  test('more completed orders wins when ratings are alike', () {
    final ranked = ProductRecommendationService.rank({
      'few': product(orders: 3, rating: 4.5, reviews: 3),
      'many': product(orders: 25, rating: 4.5, reviews: 3),
    });
    expect(ranked, ['many', 'few']);
  });

  test('a huge order count is an edge, not total domination', () {
    final scores = ProductRecommendationService.scoreProducts({
      'giant': product(orders: 2000),
      'solid': product(orders: 200),
    });
    // 10x the orders, but nowhere near 10x the sales score.
    expect(scores['solid']! / scores['giant']!, greaterThan(0.6));
  });

  test('every score stays between 0 and 1', () {
    final scores = ProductRecommendationService.scoreProducts({
      'best': product(orders: 500, rating: 5, reviews: 200),
      'none': product(),
    });
    expect(scores['best'], lessThanOrEqualTo(1));
    expect(scores['best'], greaterThan(0.9));
    expect(scores['none'], 0);
  });

  test('archived, suspended and out-of-stock listings are left out', () {
    final ranked = ProductRecommendationService.rank({
      'ok': product(orders: 1),
      'archived': product(orders: 99, archived: true),
      'suspended': product(orders: 99, suspended: true),
      'sold_out': product(orders: 99, quantity: 0),
    });
    expect(ranked, ['ok']);
  });

  test('with no sales or reviews yet: most viewed, then newest', () {
    final ranked = ProductRecommendationService.rank({
      'old': product(created: DateTime(2026, 9, 1)),
      'new': product(created: DateTime(2026, 10, 1)),
      'viewed': product(views: 12, created: DateTime(2026, 8, 1)),
    });
    expect(ranked, ['viewed', 'new', 'old']);
  });

  test('missing or bad fields count as zero, not a crash', () {
    final ranked = ProductRecommendationService.rank({
      'bare': {'quantity': 5},
      'negative': {'quantity': 5, 'completedOrderCount': -4, 'rating': 9},
      'good': product(orders: 2, rating: 4, reviews: 2),
    });
    expect(ranked.first, 'good');
    expect(ranked.length, 3);
  });
}
