import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple, live-Firestore-derived predictive analytics — a statistical
/// trend (least-squares slope over recent weekly buckets) in the same
/// no-training-required style as PriceRecommendationService, not a trained
/// ML model. Two signals, both grouped by product name:
///
/// - PRICE MOVEMENT (see DashboardAnalyticsService's canonical
///   definitions): weekly average completed-order unit price, trended,
///   for ONE [pricingType] at a time — retail and wholesale unit prices
///   for the same commodity are never averaged together, since they
///   aren't comparable numbers. Prefers each order's completedAt (falling
///   back to updatedAt, then createdAt).
/// - LOCAL SUPPLY TREND: weekly count of new active listings, trended —
///   there's no historical inventory snapshot to look back on, so "new
///   supply being added per week" is the honest, computable proxy for
///   whether local supply is expanding or contracting.
///
/// A commodity with too little history (fewer than 2 weeks of data) still
/// shows up with whatever it has, but its projection stays null rather
/// than inventing a number from one data point.
enum TrendDirection { rising, falling, stable }

class CommodityTrend {
  final String name;
  final TrendDirection priceDirection;
  final double? currentAvgPrice;
  final double? projectedNextPrice;
  final TrendDirection supplyDirection;
  final int newListingsThisWeek;
  final int projectedNextWeekListings;

  const CommodityTrend({
    required this.name,
    required this.priceDirection,
    required this.currentAvgPrice,
    required this.projectedNextPrice,
    required this.supplyDirection,
    required this.newListingsThisWeek,
    required this.projectedNextWeekListings,
  });
}

class MarketTrendService {
  static const int weeksOfHistory = 6;
  // A slope smaller than this, relative to the series' own typical size,
  // reads as noise rather than a real trend.
  static const double _stableThreshold = 0.03;

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  // When an order actually became 'completed' — mirrors
  // DashboardAnalyticsService._completionDate.
  static DateTime? _completionDate(Map<String, dynamic> order) =>
      _toDateTime(order['completedAt']) ??
      _toDateTime(order['updatedAt']) ??
      _toDateTime(order['createdAt']);

  static double _num(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  // Least-squares slope of y against x = 0, 1, 2, ... (oldest to newest).
  static double _slope(List<double> y) {
    final n = y.length;
    if (n < 2) return 0;
    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
    for (var i = 0; i < n; i++) {
      sumX += i;
      sumY += y[i];
      sumXY += i * y[i];
      sumXX += i * i;
    }
    final denom = n * sumXX - sumX * sumX;
    if (denom == 0) return 0;
    return (n * sumXY - sumX * sumY) / denom;
  }

  static TrendDirection _direction(double slope, double typicalMagnitude) {
    final scale = typicalMagnitude.abs() < 1e-9 ? 1.0 : typicalMagnitude.abs();
    final relative = slope / scale;
    if (relative > _stableThreshold) return TrendDirection.rising;
    if (relative < -_stableThreshold) return TrendDirection.falling;
    return TrendDirection.stable;
  }

  /// [completedOrders] and [activeProducts] are raw Firestore doc data
  /// (`.data()`), not query snapshots — keeps this pure and easy to feed
  /// from any screen that already streams those collections.
  static List<CommodityTrend> commodityTrends({
    required List<Map<String, dynamic>> completedOrders,
    required List<Map<String, dynamic>> activeProducts,
    required DateTime now,
    int topN = 6,
    String pricingType = 'retail',
  }) {
    // 0 = the last 7 days, 1 = the 7 days before that, ... a rolling window
    // back from [now], not calendar-week-aligned buckets.
    int bucketOf(DateTime date) {
      final daysAgo = DateTime(now.year, now.month, now.day)
          .difference(DateTime(date.year, date.month, date.day))
          .inDays;
      if (daysAgo < 0) return -1;
      return daysAgo ~/ 7;
    }

    final displayName = <String, String>{};
    final priceBuckets = <String, Map<int, List<double>>>{};
    final orderCountByName = <String, int>{};

    for (final order in completedOrders) {
      final rawName = (order['productName'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;
      // Same commodity, same pricing type — never mix retail and
      // wholesale unit prices into one weekly average.
      final orderPricingType = (order['pricingType'] ?? 'retail').toString().toLowerCase();
      if (orderPricingType != pricingType) continue;
      final key = rawName.toLowerCase();
      displayName.putIfAbsent(key, () => rawName);
      orderCountByName[key] = (orderCountByName[key] ?? 0) + 1;

      final createdAt = _completionDate(order);
      final price = _num(order['unitPrice']);
      if (createdAt == null || price <= 0) continue;
      final bucket = bucketOf(createdAt);
      if (bucket < 0 || bucket >= weeksOfHistory) continue;
      priceBuckets.putIfAbsent(key, () => {}).putIfAbsent(bucket, () => []).add(price);
    }

    final supplyBuckets = <String, Map<int, int>>{};
    for (final product in activeProducts) {
      final rawName = (product['name'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;
      final key = rawName.toLowerCase();
      displayName.putIfAbsent(key, () => rawName);

      final createdAt = _toDateTime(product['createdAt']);
      if (createdAt == null) continue;
      final bucket = bucketOf(createdAt);
      if (bucket < 0 || bucket >= weeksOfHistory) continue;
      final byBucket = supplyBuckets.putIfAbsent(key, () => {});
      byBucket[bucket] = (byBucket[bucket] ?? 0) + 1;
    }

    final names = <String>{...priceBuckets.keys, ...supplyBuckets.keys};
    final results = <CommodityTrend>[];

    for (final key in names) {
      // ---- price trend: only weeks with an actual sale, oldest→newest ----
      final pBuckets = priceBuckets[key] ?? const {};
      final weeklyAverages = <double>[];
      for (var b = weeksOfHistory - 1; b >= 0; b--) {
        final list = pBuckets[b];
        if (list != null && list.isNotEmpty) {
          weeklyAverages.add(list.reduce((a, b2) => a + b2) / list.length);
        }
      }
      double? currentAvgPrice;
      double? projectedNextPrice;
      var priceDirection = TrendDirection.stable;
      if (weeklyAverages.isNotEmpty) {
        currentAvgPrice = weeklyAverages.last;
        if (weeklyAverages.length >= 2) {
          final slope = _slope(weeklyAverages);
          final mean = weeklyAverages.reduce((a, b2) => a + b2) / weeklyAverages.length;
          priceDirection = _direction(slope, mean);
          final projected = currentAvgPrice + slope;
          projectedNextPrice = projected < 0 ? 0.0 : projected;
        }
      }

      // ---- supply trend: every week counts, zeros included ----
      final sBuckets = supplyBuckets[key] ?? const {};
      final weeklyCounts = List.generate(
        weeksOfHistory,
        (i) => (sBuckets[weeksOfHistory - 1 - i] ?? 0).toDouble(),
      );
      final thisWeekCount = sBuckets[0] ?? 0;
      final supplySlope = _slope(weeklyCounts);
      final supplyMean = weeklyCounts.reduce((a, b2) => a + b2) / weeklyCounts.length;
      final supplyDirection = _direction(supplySlope, supplyMean);
      final projectedNextWeekListings = (thisWeekCount + supplySlope).round();

      if (weeklyAverages.isEmpty && sBuckets.isEmpty) continue;

      results.add(CommodityTrend(
        name: displayName[key] ?? key,
        priceDirection: priceDirection,
        currentAvgPrice: currentAvgPrice,
        projectedNextPrice: projectedNextPrice,
        supplyDirection: supplyDirection,
        newListingsThisWeek: thisWeekCount,
        projectedNextWeekListings: projectedNextWeekListings < 0 ? 0 : projectedNextWeekListings,
      ));
    }

    results.sort((a, b) =>
        (orderCountByName[b.name.toLowerCase()] ?? 0).compareTo(orderCountByName[a.name.toLowerCase()] ?? 0));

    return results.take(topN).toList();
  }
}
