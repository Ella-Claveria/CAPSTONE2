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

  group('PriceRecommendationService.recommend — cold start (no marketplace data)', () {
    test('nothing at all -> insufficient, no numbers', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [],
        transactions: [],
        reference: null,
      );
      expect(result.tier, PriceDataTier.insufficient);
      expect(result.suggestedPrice, isNull);
    });

    test('reference price alone -> referenceOnly, suggested price IS the reference price', () {
      final reference = PriceRecommendationService.referenceInfo(
        price: 70,
        effectiveDate: DateTime(2026, 1, 1),
        now: DateTime(2026, 1, 15),
      )!;
      final result = PriceRecommendationService.recommend(
        listingPrices: [],
        transactions: [],
        reference: reference,
      );

      expect(result.tier, PriceDataTier.referenceOnly);
      expect(result.tier.dataAvailabilityLabel, 'Limited Data');
      expect(result.suggestedPrice, 70);
      expect(result.referencePrice, 70);
      // Conservative, symmetric, and driven by the one named constant —
      // never a guessed spread.
      expect(result.suggestedLow, closeTo(70 * (1 - PriceRecommendationService.coldStartRangePct), 0.001));
      expect(result.suggestedHigh, closeTo(70 * (1 + PriceRecommendationService.coldStartRangePct), 0.001));
      expect(result.listingCount, 0);
      expect(result.transactionCount, 0);
    });

    test('a stale reference price is flagged but still used', () {
      final reference = PriceRecommendationService.referenceInfo(
        price: 70,
        effectiveDate: DateTime(2025, 1, 1),
        now: DateTime(2026, 1, 1),
      )!;
      final result = PriceRecommendationService.recommend(
        listingPrices: [],
        transactions: [],
        reference: reference,
      );

      expect(result.referenceIsStale, isTrue);
      expect(result.suggestedPrice, 70);
    });
  });

  group('PriceRecommendationService.recommend — maturing marketplace', () {
    test('listings + transactions (no reference) compute a real suggested price/range', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [180, 200, 220],
        transactions: [(price: 190, date: null), (price: 210, date: null)],
        reference: null,
      );

      expect(result.tier, PriceDataTier.full);
      expect(result.suggestedPrice, isNotNull);
      expect(result.listingCount, 3);
      expect(result.transactionCount, 2);
      expect(result.suggestedLow, lessThanOrEqualTo(result.suggestedPrice!));
      expect(result.suggestedHigh, greaterThanOrEqualTo(result.suggestedPrice!));
      expect(result.marketplaceLow, 180);
      expect(result.marketplaceHigh, 220);
    });

    test('flags "limited" tier under 3 listings/transactions', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [200],
        transactions: [(price: 210, date: null)],
        reference: null,
      );

      expect(result.tier, PriceDataTier.limited);
      expect(result.tier.dataAvailabilityLabel, 'Moderate Data');
    });

    test('reaches "full" tier once 3+ listings exist', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [200, 205, 208],
        transactions: [(price: 210, date: null)],
        reference: null,
      );

      expect(result.tier, PriceDataTier.full);
      expect(result.tier.dataAvailabilityLabel, 'Strong Data Support');
    });

    test('reference price pulls the suggested price toward the official figure', () {
      final withoutReference = PriceRecommendationService.recommend(
        listingPrices: [100, 150, 400],
        transactions: [],
        reference: null,
      );
      final withReference = PriceRecommendationService.recommend(
        listingPrices: [100, 150, 400],
        transactions: [],
        reference: const ReferencePriceInfo(price: 250, effectiveDate: null, isStale: false),
      );

      expect(withReference.referencePrice, 250);
      expect(
        (withReference.suggestedPrice! - 250).abs(),
        lessThan((withoutReference.suggestedPrice! - 250).abs()),
      );
    });

    test('completed transactions outweigh active listings once there are enough of them', () {
      // 3+ transactions all near 300, listings scattered far from it —
      // the weighted median should land close to the transaction cluster.
      final result = PriceRecommendationService.recommend(
        listingPrices: [100, 500],
        transactions: [
          (price: 298, date: null),
          (price: 300, date: null),
          (price: 302, date: null),
        ],
        reference: null,
      );

      expect((result.suggestedPrice! - 300).abs(), lessThan(50));
    });

    test('falls back to a real listing-count-derived supply signal, never a fabricated one', () {
      final result = PriceRecommendationService.recommend(
        listingPrices: [200, 205, 210],
        transactions: [],
        reference: null,
        supplyQuantity: null,
        searchCount30d: 0,
      );

      // No explicit supplyQuantity was given, but 3 REAL active listings
      // still counts as a real (if approximate) supply signal.
      expect(result.usedSupplyDemand, isTrue);
    });
  });
}
