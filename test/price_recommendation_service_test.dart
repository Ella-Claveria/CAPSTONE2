import 'package:flutter_test/flutter_test.dart';

import 'package:agritrade/services/price_recommendation_service.dart';

void main() {
  group('PriceRecommendationService.namesLikelyMatch', () {
    test('matches when one name contains the other', () {
      expect(
        PriceRecommendationService.namesLikelyMatch('Rice', 'Jasmine Rice'),
        isTrue,
      );
    });

    test('matches on a shared significant word', () {
      expect(
        PriceRecommendationService.namesLikelyMatch(
          'Premium Free-Range Chicken',
          'Native Chicken Eggs',
        ),
        isTrue,
      );
    });

    test('does not match on shared generic descriptors alone', () {
      expect(
        PriceRecommendationService.namesLikelyMatch(
          'Free-Range Chicken',
          'Free-Range Duck',
        ),
        isFalse,
      );
    });

    test('unrelated products do not match', () {
      expect(
        PriceRecommendationService.namesLikelyMatch('Chicken', 'Cabbage'),
        isFalse,
      );
    });

    test('empty input never matches', () {
      expect(PriceRecommendationService.namesLikelyMatch('', 'Rice'), isFalse);
      expect(PriceRecommendationService.namesLikelyMatch('Rice', ''), isFalse);
    });
  });

  group('PriceRecommendationService.recommend', () {
    test('returns null with no listings, sales, or baseline', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [],
        transactionPrices: [],
        baselinePrice: null,
      );
      expect(result, isNull);
    });

    test('computes median and range from combined listings + sales', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [180, 200, 220],
        transactionPrices: [190, 210],
        baselinePrice: null,
      );

      expect(result, isNotNull);
      expect(result!.median, 200);
      expect(result.listingCount, 3);
      expect(result.transactionCount, 2);
      expect(result.hasBaseline, isFalse);
      expect(result.low, lessThanOrEqualTo(result.median));
      expect(result.high, greaterThanOrEqualTo(result.median));
    });

    test('flags limitedData when fewer than 3 real price points exist', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [200],
        transactionPrices: [210],
        baselinePrice: null,
      );

      expect(result, isNotNull);
      expect(result!.limitedData, isTrue);
    });

    test('does not flag limitedData once 3+ real price points exist', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [200, 205],
        transactionPrices: [210],
        baselinePrice: null,
      );

      expect(result, isNotNull);
      expect(result!.limitedData, isFalse);
    });

    test('baseline price pulls the median toward the official price', () {
      final withoutBaseline = PriceRecommendationService.recommend(
        listingPrices: [100, 150, 400],
        transactionPrices: [],
        baselinePrice: null,
      )!;
      final withBaseline = PriceRecommendationService.recommend(
        listingPrices: [100, 150, 400],
        transactionPrices: [],
        baselinePrice: 250,
      )!;

      expect(withBaseline.hasBaseline, isTrue);
      expect(withBaseline.baselinePrice, 250);
      // Anchoring on 250 (counted twice) should pull the median closer to
      // 250 than the unanchored median of 100/400 is.
      expect(
        (withBaseline.median - 250).abs(),
        lessThan((withoutBaseline.median - 250).abs()),
      );
    });

    test('a baseline alone (no listings/sales) still produces a recommendation', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [],
        transactionPrices: [],
        baselinePrice: 50,
      );

      expect(result, isNotNull);
      expect(result!.median, 50);
      expect(result.listingCount, 0);
      expect(result.transactionCount, 0);
      expect(result.hasBaseline, isTrue);
      expect(result.limitedData, isTrue);
    });
  });
}
