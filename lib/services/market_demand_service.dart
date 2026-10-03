import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/commodity_master_list.dart';

/// Marketplace-wide demand analytics for the Farmer Dashboard: Best-Selling
/// Products and Top Buyer Locations.
///
/// Everything is computed from `market_sales` — the anonymized mirror of
/// completed orders across all farmers that the recordMarketSale Cloud
/// Function maintains (a farmer can't read other farmers' orders). Only
/// completed orders are in it, so nothing pending, rejected or cancelled is
/// ever counted. It carries the commodity, order type and the buyer's
/// general area (municipality/city) — never who the buyer or seller was.
///
/// Commodities are resolved through [CommodityRegistry] (the Admin-managed
/// list), so one the Admin adds becomes eligible as soon as a completed
/// order exists for it; there is no list of products in here.

enum DemandLevel { high, moderate, low }

enum DemandTrend { rising, stable, declining }

class BestSeller {
  final String commodity;
  final String category;
  final String unit;

  /// True/false when the order type is on record for these sales; null for
  /// sales recorded before it was kept.
  final bool? mostlyWholesale;

  /// The buyer area with the most completed orders for this commodity, or
  /// '' when no buyer area is on record.
  final String topBuyerArea;
  final DemandLevel demand;
  final DemandTrend trend;

  const BestSeller({
    required this.commodity,
    required this.category,
    required this.unit,
    required this.mostlyWholesale,
    required this.topBuyerArea,
    required this.demand,
    required this.trend,
  });
}

class BuyerLocation {
  final String area;

  /// 0–1: this area's completed orders relative to the top area's.
  final double relativeDemand;
  final String mostPurchased;
  final DemandLevel demand;

  const BuyerLocation({
    required this.area,
    required this.relativeDemand,
    required this.mostPurchased,
    required this.demand,
  });
}

/// One completed order as recorded in `market_sales`, with its commodity
/// resolved against the Admin-managed list.
class MarketSale {
  final String commodity;
  final String category;
  final String unit;
  final bool? wholesale;
  final String area;
  final DateTime date;

  const MarketSale(
    this.commodity,
    this.category,
    this.unit,
    this.wholesale,
    this.area,
    this.date,
  );
}

class MarketDemandService {
  const MarketDemandService._();

  static const int bestSellerLimit = 10;
  static const int locationLimit = 10;

  static List<MarketSale> parseSales(Iterable<Map<String, dynamic>> records) {
    final sales = <MarketSale>[];
    for (final record in records) {
      if ((record['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      final name = (record['productName'] ?? '').toString().trim();
      final date = record['completedAt'] ?? record['createdAt'];
      if (name.isEmpty || date is! Timestamp) continue;

      // "Fresh Native Tomato" and "Tomato" are the same commodity.
      final commodity = matchSupportedCommodity(name) ?? name;
      final category =
          categoryOfCommodity(commodity) ??
          (record['category'] ?? '').toString().trim();
      final unit = (record['unit'] ?? '').toString().trim();
      final pricing = (record['pricingType'] ?? '').toString().toLowerCase();
      sales.add(
        MarketSale(
          commodity,
          category,
          unit.isEmpty ? unitForCommodity(commodity) : unit,
          pricing.isEmpty ? null : pricing == 'wholesale',
          (record['buyerArea'] ?? '').toString().trim(),
          date.toDate(),
        ),
      );
    }
    return sales;
  }

  static bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  /// Demand relative to the busiest entry of the same list and period:
  /// High at two-thirds of its completed orders or more, Moderate at
  /// one-third or more, otherwise Low.
  static DemandLevel _level(int orders, int topOrders) {
    final share = topOrders == 0 ? 0 : orders / topOrders;
    if (share >= 2 / 3) return DemandLevel.high;
    if (share >= 1 / 3) return DemandLevel.moderate;
    return DemandLevel.low;
  }

  /// Completed orders this period against the same stretch of the month
  /// before: more than 10% up is Rising, more than 10% down is Declining.
  static DemandTrend _trend(int current, int previous) {
    if (previous == 0) {
      return current > 0 ? DemandTrend.rising : DemandTrend.stable;
    }
    final change = (current - previous) / previous;
    if (change > 0.10) return DemandTrend.rising;
    if (change < -0.10) return DemandTrend.declining;
    return DemandTrend.stable;
  }

  static String _mostCommon(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      if (value.isNotEmpty) counts[value] = (counts[value] ?? 0) + 1;
    }
    var best = '';
    var bestCount = 0;
    counts.forEach((value, n) {
      if (n > bestCount) {
        best = value;
        bestCount = n;
      }
    });
    return best;
  }

  /// The top commodities by completed orders in [month], across every
  /// farmer. Ranked by number of completed orders — quantities aren't
  /// comparable between a per-kg and a per-head commodity.
  static List<BestSeller> bestSellers({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    DateTime? now,
  }) {
    final all = parseSales(sales);
    final today = now ?? DateTime.now();
    final previousMonth = DateTime(month.year, month.month - 1);
    // For the month still in progress, compare like with like: the same
    // number of days of the previous month, not all of it.
    final isCurrentMonth = _inMonth(today, month);
    bool inPrevious(DateTime date) =>
        _inMonth(date, previousMonth) &&
        (!isCurrentMonth || date.day <= today.day);

    final byCommodity = <String, List<MarketSale>>{};
    final previousCount = <String, int>{};
    for (final sale in all) {
      final key = sale.commodity.toLowerCase();
      if (_inMonth(sale.date, month)) {
        byCommodity.putIfAbsent(key, () => []).add(sale);
      } else if (inPrevious(sale.date)) {
        previousCount[key] = (previousCount[key] ?? 0) + 1;
      }
    }

    final ranked = byCommodity.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.length.compareTo(a.value.length);
        return byOrders != 0
            ? byOrders
            : a.value.first.commodity.compareTo(b.value.first.commodity);
      });
    if (ranked.isEmpty) return const [];
    final topOrders = ranked.first.value.length;

    return [
      for (final entry in ranked.take(bestSellerLimit))
        () {
          final orders = entry.value;
          final typed = orders.where((s) => s.wholesale != null).toList();
          final wholesale = typed.where((s) => s.wholesale!).length;
          return BestSeller(
            commodity: orders.first.commodity,
            category: orders.first.category,
            unit: _mostCommon(orders.map((s) => s.unit)),
            mostlyWholesale: typed.isEmpty
                ? null
                : wholesale > typed.length - wholesale,
            topBuyerArea: _mostCommon(orders.map((s) => s.area)),
            demand: _level(orders.length, topOrders),
            trend: _trend(orders.length, previousCount[entry.key] ?? 0),
          );
        }(),
    ];
  }

  /// The buyer areas with the most completed orders in [month]. Sales with
  /// no buyer area on record are left out rather than guessed.
  static List<BuyerLocation> topBuyerLocations({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
  }) {
    final byArea = <String, List<MarketSale>>{};
    for (final sale in parseSales(sales)) {
      if (sale.area.isEmpty || !_inMonth(sale.date, month)) continue;
      byArea.putIfAbsent(sale.area, () => []).add(sale);
    }
    final ranked = byArea.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.length.compareTo(a.value.length);
        return byOrders != 0 ? byOrders : a.key.compareTo(b.key);
      });
    if (ranked.isEmpty) return const [];
    final topOrders = ranked.first.value.length;

    return [
      for (final entry in ranked.take(locationLimit))
        BuyerLocation(
          area: entry.key,
          relativeDemand: entry.value.length / topOrders,
          mostPurchased: _mostCommon(entry.value.map((s) => s.commodity)),
          demand: _level(entry.value.length, topOrders),
        ),
    ];
  }
}
