import 'package:flutter_test/flutter_test.dart';

import 'package:agritrade/services/product_visibility_service.dart';

void main() {
  Map<String, dynamic> product({
    required String farmerId,
    double rating = 0,
    int reviewCount = 0,
    int viewCount = 0,
  }) {
    return {
      'farmerId': farmerId,
      'rating': rating,
      'reviewCount': reviewCount,
      'viewCount': viewCount,
    };
  }

  group('ProductVisibilityService.scoreProducts', () {
    test('returns nothing for an empty product set', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {},
        completedOrderCountByProductId: {},
        verifiedByFarmerId: {},
      );
      expect(scores, isEmpty);
    });

    test('a single product scores zero either way — nothing to rank against', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {'p1': product(farmerId: 'f1', rating: 5, reviewCount: 10, viewCount: 100)},
        completedOrderCountByProductId: {'p1': 50},
        verifiedByFarmerId: {'f1': true},
      );
      expect(scores['p1'], 0.0);
    });

    test('higher demand (completed orders) ranks a product above a quieter one', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {
          'popular': product(farmerId: 'f1'),
          'quiet': product(farmerId: 'f2'),
        },
        completedOrderCountByProductId: {'popular': 20, 'quiet': 1},
        verifiedByFarmerId: {},
      );
      expect(scores['popular']!, greaterThan(scores['quiet']!));
    });

    test('a verified, highly-rated seller outranks an unverified, unrated one on credibility alone', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {
          'trusted': product(farmerId: 'f1', rating: 4.8, reviewCount: 20),
          'new_seller': product(farmerId: 'f2'),
        },
        completedOrderCountByProductId: {},
        verifiedByFarmerId: {'f1': true, 'f2': false},
      );
      expect(scores['trusted']!, greaterThan(scores['new_seller']!));
    });

    test('seller credibility is shared across a seller\'s own listings', () {
      // f1 has one well-reviewed product and one brand-new one; the new
      // one should still benefit from f1's established reputation.
      final scores = ProductVisibilityService.scoreProducts(
        products: {
          'established': product(farmerId: 'f1', rating: 5, reviewCount: 30),
          'new_listing': product(farmerId: 'f1'),
          'unrelated': product(farmerId: 'f2'),
        },
        completedOrderCountByProductId: {},
        verifiedByFarmerId: {},
      );
      expect(scores['new_listing']!, greaterThan(scores['unrelated']!));
    });

    test('more views (interaction) contributes to a higher score', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {
          'viewed': product(farmerId: 'f1', viewCount: 500),
          'unseen': product(farmerId: 'f2', viewCount: 0),
        },
        completedOrderCountByProductId: {},
        verifiedByFarmerId: {},
      );
      expect(scores['viewed']!, greaterThan(scores['unseen']!));
    });

    test('identical products across the board score identically', () {
      final scores = ProductVisibilityService.scoreProducts(
        products: {
          'a': product(farmerId: 'f1', rating: 4, reviewCount: 5, viewCount: 10),
          'b': product(farmerId: 'f2', rating: 4, reviewCount: 5, viewCount: 10),
        },
        completedOrderCountByProductId: {'a': 3, 'b': 3},
        verifiedByFarmerId: {'f1': true, 'f2': true},
      );
      expect(scores['a'], scores['b']);
    });
  });
}
