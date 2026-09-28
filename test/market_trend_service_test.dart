import 'package:flutter_test/flutter_test.dart';

import 'package:agritrade/services/market_trend_service.dart';

void main() {
  final now = DateTime(2026, 9, 22, 12); // an arbitrary Tuesday

  Map<String, dynamic> order({required String name, required num price, required DateTime at}) {
    return {'productName': name, 'unitPrice': price, 'createdAt': at};
  }

  Map<String, dynamic> product({required String name, required DateTime at}) {
    return {'name': name, 'createdAt': at};
  }

  group('MarketTrendService.commodityTrends', () {
    test('returns nothing with no orders or listings', () {
      final result = MarketTrendService.commodityTrends(
        completedOrders: [],
        activeProducts: [],
        now: now,
      );
      expect(result, isEmpty);
    });

    test('detects a rising price trend and projects a higher next price', () {
      final orders = [
        order(name: 'Tomato', price: 40, at: now.subtract(const Duration(days: 21))),
        order(name: 'Tomato', price: 45, at: now.subtract(const Duration(days: 14))),
        order(name: 'Tomato', price: 50, at: now.subtract(const Duration(days: 7))),
        order(name: 'Tomato', price: 55, at: now),
      ];
      final result = MarketTrendService.commodityTrends(
        completedOrders: orders,
        activeProducts: [],
        now: now,
      );
      expect(result, hasLength(1));
      final tomato = result.first;
      expect(tomato.name, 'Tomato');
      expect(tomato.priceDirection, TrendDirection.rising);
      expect(tomato.currentAvgPrice, 55);
      expect(tomato.projectedNextPrice, greaterThan(55));
    });

    test('detects a falling price trend', () {
      final orders = [
        order(name: 'Cabbage', price: 60, at: now.subtract(const Duration(days: 21))),
        order(name: 'Cabbage', price: 50, at: now.subtract(const Duration(days: 14))),
        order(name: 'Cabbage', price: 40, at: now.subtract(const Duration(days: 7))),
        order(name: 'Cabbage', price: 30, at: now),
      ];
      final result = MarketTrendService.commodityTrends(
        completedOrders: orders,
        activeProducts: [],
        now: now,
      );
      final cabbage = result.first;
      expect(cabbage.priceDirection, TrendDirection.falling);
      expect(cabbage.projectedNextPrice, lessThan(30));
    });

    test('a single week of sales has no projection, but is not fabricated', () {
      final orders = [order(name: 'Onion', price: 100, at: now)];
      final result = MarketTrendService.commodityTrends(
        completedOrders: orders,
        activeProducts: [],
        now: now,
      );
      final onion = result.first;
      expect(onion.priceDirection, TrendDirection.stable);
      expect(onion.currentAvgPrice, 100);
      expect(onion.projectedNextPrice, isNull);
    });

    test('detects a rising supply trend from new listing counts per week', () {
      final products = [
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 21))),
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 14))),
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 14))),
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 7))),
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 7))),
        product(name: 'Eggplant', at: now.subtract(const Duration(days: 7))),
        product(name: 'Eggplant', at: now),
        product(name: 'Eggplant', at: now),
        product(name: 'Eggplant', at: now),
        product(name: 'Eggplant', at: now),
      ];
      final result = MarketTrendService.commodityTrends(
        completedOrders: [],
        activeProducts: products,
        now: now,
      );
      final eggplant = result.first;
      expect(eggplant.supplyDirection, TrendDirection.rising);
      expect(eggplant.newListingsThisWeek, 4);
      expect(eggplant.projectedNextWeekListings, greaterThanOrEqualTo(eggplant.newListingsThisWeek));
    });

    test('ranks commodities by completed-order volume, most active first', () {
      final orders = [
        for (var i = 0; i < 5; i++) order(name: 'Popular Rice', price: 40, at: now),
        order(name: 'Rare Herb', price: 200, at: now),
      ];
      final result = MarketTrendService.commodityTrends(
        completedOrders: orders,
        activeProducts: [],
        now: now,
        topN: 6,
      );
      expect(result.first.name, 'Popular Rice');
    });

    test('respects topN', () {
      final orders = [
        for (var i = 0; i < 10; i++) order(name: 'Product $i', price: 10, at: now),
      ];
      final result = MarketTrendService.commodityTrends(
        completedOrders: orders,
        activeProducts: [],
        now: now,
        topN: 3,
      );
      expect(result, hasLength(3));
    });
  });
}
