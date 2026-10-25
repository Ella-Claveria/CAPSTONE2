import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/commodity_master_list.dart';
import 'historical_demand_service.dart';

/// Where a price on the Price Trend chart came from.
enum PriceTrendSource {
  /// A farmer's listing: its retail asking price when posted or last edited.
  farmerListing,

  /// A completed order: the retail unit price the buyer paid.
  farmerSale,

  /// A reference price the Admin set in Price Management, on its date.
  adminReference,

  /// A monthly average price in the Admin's imported historical data.
  adminImport,
}

/// One price of a commodity on a date.
class PriceTrendPoint {
  final DateTime date;
  final double price;
  final PriceTrendSource source;

  const PriceTrendPoint(this.date, this.price, this.source);
}

/// Admin → Market Trends → Price Trend: a commodity's average price month by
/// month, one year against another (e.g. 2025 against 2026), from every
/// price on record for it — the prices farmers used (their listings and
/// completed sales) and the prices the Admin entered (Price Management's
/// dated reference prices and imported historical data). Each counts in the
/// month of its own date. Nothing is estimated: a month with no price on
/// record has no point.
///
/// Only prices in the commodity's own unit count (a per-head livestock
/// price never mixes with a per-kg one), and only retail prices: wholesale
/// is a bulk discount, not the market price.
class PriceTrendService {
  const PriceTrendService._();

  /// The first pair of years the chart compares.
  static const int firstYear = 2025;

  /// The year pairs to choose from, oldest first: 2025 against 2026, then
  /// one more each year up to the current one.
  static List<({int previous, int current})> yearPairs(DateTime now) {
    final last = now.year < firstYear + 1 ? firstYear + 1 : now.year;
    return [
      for (var year = firstYear + 1; year <= last; year++)
        (previous: year - 1, current: year),
    ];
  }

  static String _key(String text) => text.trim().toLowerCase();

  static bool _isCommodity(
    Map<String, dynamic> data,
    String nameField,
    String commodity,
  ) {
    final stored = (data['commodity'] ?? '').toString().trim();
    final name = stored.isNotEmpty
        ? stored
        : (data[nameField] ?? '').toString();
    final matched = matchSupportedCommodity(name) ?? name;
    return _key(matched) == _key(commodity);
  }

  // A blank unit is taken as the commodity's own (older records).
  static bool _sameUnit(Object? unit, String commodityUnit) {
    final text = (unit ?? '').toString().trim();
    return text.isEmpty || _key(text) == _key(commodityUnit);
  }

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : (value is DateTime ? value : null);

  static double? _price(Object? value) {
    final price = value is num ? value.toDouble() : null;
    return price != null && price > 0 ? price : null;
  }

  /// Every price on record for [commodity]. [referenceHistory] is the
  /// commodity's `market_prices/{id}/history` entries.
  static List<PriceTrendPoint> collect({
    required String commodity,
    required Iterable<Map<String, dynamic>> products,
    required Iterable<Map<String, dynamic>> completedOrders,
    required Iterable<Map<String, dynamic>> referenceHistory,
    required Iterable<HistoricalDemandRecord> historical,
  }) {
    final unit = unitForCommodity(commodity);
    final points = <PriceTrendPoint>[];

    for (final listing in products) {
      if (!_isCommodity(listing, 'name', commodity)) continue;
      if (!_sameUnit(listing['unit'], unit)) continue;
      final price = _price(listing['retailPrice'] ?? listing['price']);
      final date = _date(listing['updatedAt']) ?? _date(listing['createdAt']);
      if (price == null || date == null) continue;
      points.add(PriceTrendPoint(date, price, PriceTrendSource.farmerListing));
    }

    for (final order in completedOrders) {
      if (!_isCommodity(order, 'productName', commodity)) continue;
      if (!_sameUnit(order['unit'], unit)) continue;
      if ((order['pricingType'] ?? '').toString().toLowerCase() ==
          'wholesale') {
        continue;
      }
      final price = _price(order['pricePerUnit'] ?? order['unitPrice']);
      final date = _date(order['completedAt']) ?? _date(order['createdAt']);
      if (price == null || date == null) continue;
      points.add(PriceTrendPoint(date, price, PriceTrendSource.farmerSale));
    }

    for (final entry in referenceHistory) {
      if (!_sameUnit(entry['unit'], unit)) continue;
      final price = _price(entry['price']);
      final date = _date(entry['effectiveDate']);
      if (price == null || date == null) continue;
      points.add(PriceTrendPoint(date, price, PriceTrendSource.adminReference));
    }

    for (final record in historical) {
      if (_key(record.commodity) != _key(commodity)) continue;
      if (!_sameUnit(record.unit, unit)) continue;
      final price = _price(record.averagePrice);
      if (price == null) continue;
      points.add(
        PriceTrendPoint(
          DateTime(record.year, record.month),
          price,
          PriceTrendSource.adminImport,
        ),
      );
    }
    return points;
  }

  /// The average price in each month of [year], January first; null for a
  /// month with no price on record.
  static List<double?> monthlyAverages(
    Iterable<PriceTrendPoint> points,
    int year,
  ) {
    final sums = List<double>.filled(12, 0);
    final counts = List<int>.filled(12, 0);
    for (final point in points) {
      if (point.date.year != year) continue;
      sums[point.date.month - 1] += point.price;
      counts[point.date.month - 1]++;
    }
    return [
      for (var m = 0; m < 12; m++) counts[m] == 0 ? null : sums[m] / counts[m],
    ];
  }

  /// The average of a year's monthly averages, or null with none.
  static double? yearAverage(List<double?> monthly) {
    final known = monthly.whereType<double>().toList();
    if (known.isEmpty) return null;
    return known.reduce((a, b) => a + b) / known.length;
  }
}
