import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/commodity_master_list.dart';

enum FarmerRevenueView { weekly, monthly }

class FarmerRevenueService {
  const FarmerRevenueService();

  static bool isBeginner({
    required DateTime registeredAt,
    required DateTime now,
  }) {
    return now.difference(registeredAt).inDays < 7;
  }

  static bool canViewMonthly({
    required DateTime registeredAt,
    required DateTime now,
  }) {
    return now.difference(registeredAt).inDays >= 30;
  }

  static FarmerRevenueView resolveView({
    required DateTime registeredAt,
    required DateTime now,
  }) {
    return isBeginner(registeredAt: registeredAt, now: now)
        ? FarmerRevenueView.weekly
        : FarmerRevenueView.monthly;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static num totalRevenueForRange({
    required List<Map<String, dynamic>> orders,
    required FarmerRevenueView view,
    required DateTime now,
  }) {
    final rangeStart = view == FarmerRevenueView.weekly
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6))
        : DateTime(now.year, now.month, 1);

    final rangeEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    var total = 0.0;
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status != 'completed') continue;

      final createdAt = _toDateTime(order['createdAt']);
      if (createdAt == null) continue;

      if (!createdAt.isBefore(rangeStart) && !createdAt.isAfter(rangeEnd)) {
        final raw = order['total'];
        final value = raw is num
            ? raw.toDouble()
            : num.tryParse(raw?.toString() ?? '')?.toDouble() ?? 0.0;
        total += value;
      }
    }

    return total;
  }

  static List<Map<String, dynamic>> revenueBars({
    required List<Map<String, dynamic>> orders,
    required FarmerRevenueView view,
    required DateTime now,
  }) {
    if (view == FarmerRevenueView.weekly) {
      final labels = <String>[];
      final values = <double>[];
      for (var i = 6; i >= 0; i--) {
        final date = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: i));
        labels.add(_dayLabel(date));
        var total = 0.0;
        for (final order in orders) {
          final status = (order['status'] ?? '').toString().toLowerCase();
          if (status != 'completed') continue;
          final createdAt = _toDateTime(order['createdAt']);
          if (createdAt == null) continue;
          final sameDay =
              createdAt.year == date.year &&
              createdAt.month == date.month &&
              createdAt.day == date.day;
          if (!sameDay) continue;
          final raw = order['total'];
          final value = raw is num
              ? raw.toDouble()
              : num.tryParse(raw?.toString() ?? '')?.toDouble() ?? 0.0;
          total += value;
        }
        values.add(total);
      }
      return List.generate(
        labels.length,
        (index) => {'label': labels[index], 'value': values[index]},
      );
    }

    final monthLabels = <String>[];
    final monthValues = <double>[];
    for (var i = 5; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      monthLabels.add(_monthLabel(monthDate));
      var total = 0.0;
      for (final order in orders) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        if (status != 'completed') continue;
        final createdAt = _toDateTime(order['createdAt']);
        if (createdAt == null) continue;
        final sameMonth =
            createdAt.year == monthDate.year &&
            createdAt.month == monthDate.month;
        if (!sameMonth) continue;
        final raw = order['total'];
        final value = raw is num
            ? raw.toDouble()
            : num.tryParse(raw?.toString() ?? '')?.toDouble() ?? 0.0;
        total += value;
      }
      monthValues.add(total);
    }
    return List.generate(
      monthLabels.length,
      (index) => {'label': monthLabels[index], 'value': monthValues[index]},
    );
  }

  /// The Philippine agricultural season for [now] — Rainy Season runs
  /// June through November, Dry Season runs December through May. This is
  /// the single reusable source of truth for "what season is it right
  /// now"; nothing in the UI should hardcode a season name.
  static String getCurrentSeason(DateTime now) {
    return (now.month >= 6 && now.month <= 11) ? 'Rainy Season' : 'Dry Season';
  }

  /// The current season's start date through [now] — e.g. in September
  /// 2026 this is June 1, 2026 through the current date. Dry Season spans
  /// a calendar-year boundary (Dec–May), so the start year is resolved
  /// from [now]'s month.
  static ({DateTime start, DateTime end}) currentSeasonRange(DateTime now) {
    if (now.month >= 6 && now.month <= 11) {
      return (start: DateTime(now.year, 6, 1), end: now);
    }
    final startYear = now.month == 12 ? now.year : now.year - 1;
    return (start: DateTime(startYear, 12, 1), end: now);
  }

  // How far back "recent marketplace activity" looks for Marketplace
  // Demand — deliberately a short rolling window (not the whole season)
  // so it never just mirrors the Top Product This Season figure.
  static const int _recentWindowDays = 30;

  static num _asNum(dynamic raw) {
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static String? _topByQuantity(Map<String, num> quantities) {
    if (quantities.isEmpty) return null;
    return quantities.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Top products by completed-order revenue, for one farmer's own orders
  /// — powers the Market tab's "Best-Selling Products" card. Mirrors the
  /// platform-wide single-product version on the admin dashboard, but
  /// scoped to a farmer's [orders] and returning a ranked list.
  static List<({String name, num revenue, num quantity})> bestSellingProducts({
    required List<Map<String, dynamic>> orders,
    int limit = 3,
  }) {
    final revenueByProduct = <String, num>{};
    final qtyByProduct = <String, num>{};
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status != 'completed') continue;
      final name = (order['productName'] ?? order['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      revenueByProduct[name] = (revenueByProduct[name] ?? 0) + _asNum(order['total']);
      qtyByProduct[name] = (qtyByProduct[name] ?? 0) + _asNum(order['quantity']);
    }
    if (revenueByProduct.isEmpty) return const [];

    final ranked = revenueByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked
        .take(limit)
        .map((e) => (name: e.key, revenue: e.value, quantity: qtyByProduct[e.key] ?? 0))
        .toList();
  }

  /// Market insights for the "Market Objective" card — entirely derived
  /// from live marketplace data (active listings + completed orders), with
  /// no hardcoded products, prices, or demand values. Any metric without
  /// enough supporting data comes back null so the UI can show an honest
  /// "not enough data" state instead of a fake number.
  static Map<String, dynamic> marketObjective({
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> orders,
    required DateTime now,
  }) {
    // ---- 1. Current Market Average — scoped to the farmer's own
    // most-listed commodity (by active listing count), never blended
    // across different commodities/units (a per-kg vegetable and a
    // per-head animal averaged together would be meaningless).
    final activePricesByCommodity = <String, List<double>>{};
    for (final product in products) {
      if (product['isArchived'] == true || product['quantity'] == null) continue;
      final price = _asNum(product['price']).toDouble();
      if (price <= 0) continue;
      final rawName = (product['commodity'] ?? product['name'] ?? '').toString().trim();
      if (rawName.isEmpty) continue;
      final commodity = matchSupportedCommodity(rawName) ?? rawName;
      activePricesByCommodity.putIfAbsent(commodity, () => []).add(price);
    }
    String? topCommodity;
    var topCount = 0;
    activePricesByCommodity.forEach((commodity, prices) {
      if (prices.length > topCount) {
        topCount = prices.length;
        topCommodity = commodity;
      }
    });
    final double? marketAverage = topCommodity == null
        ? null
        : activePricesByCommodity[topCommodity]!.reduce((a, b) => a + b) /
            activePricesByCommodity[topCommodity]!.length;
    final String? marketAverageCommodity = topCommodity;
    final String? marketAverageUnit = topCommodity == null ? null : unitForCommodity(topCommodity!);

    final completedOrders = orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      return status == 'completed' && _toDateTime(order['createdAt']) != null;
    }).toList();

    // ---- 2. Top Product This Season — total quantity sold per product,
    // for completed orders placed within the current season's start date
    // through now (e.g. in September, Rainy Season means June 1 through
    // today).
    final currentSeason = getCurrentSeason(now);
    final seasonRange = currentSeasonRange(now);
    final seasonalQuantities = <String, num>{};
    for (final order in completedOrders) {
      final createdAt = _toDateTime(order['createdAt'])!;
      if (createdAt.isBefore(seasonRange.start) || createdAt.isAfter(seasonRange.end)) {
        continue;
      }
      final name = (order['productName'] ?? order['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      seasonalQuantities[name] = (seasonalQuantities[name] ?? 0) + _asNum(order['quantity']);
    }
    final seasonalPick = _topByQuantity(seasonalQuantities);

    // ---- 3. Marketplace Demand — total quantity sold per product from
    // *recent* completed orders only (last 30 days), so it tracks what's
    // moving right now rather than repeating the seasonal figure above.
    // (No search/view tracking exists in this app yet, so purchase
    // activity is the only demand signal available.)
    final recentQuantities = <String, num>{};
    for (final order in completedOrders) {
      final createdAt = _toDateTime(order['createdAt'])!;
      if (now.difference(createdAt).inDays > _recentWindowDays) continue;
      final name = (order['productName'] ?? order['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      recentQuantities[name] = (recentQuantities[name] ?? 0) + _asNum(order['quantity']);
    }
    final marketPick = _topByQuantity(recentQuantities);

    // ---- 4. Suggested Focus — generated from whichever real signal is
    // available, favoring current demand over seasonal demand.
    final String suggestion;
    if (marketPick != null) {
      suggestion =
          'Suggested focus: Consider listing more $marketPick based on current buyer demand.';
    } else if (seasonalPick != null) {
      suggestion =
          'Suggested focus: Consider increasing your $seasonalPick listings based on seasonal demand.';
    } else {
      suggestion =
          'Suggested focus: Continue listing products while more market data is collected.';
    }

    return {
      'season': currentSeason,
      'marketAverage': marketAverage,
      'marketAverageCommodity': marketAverageCommodity,
      'marketAverageUnit': marketAverageUnit,
      'seasonalPick': seasonalPick,
      'marketPick': marketPick,
      'suggestion': suggestion,
    };
  }

  static String _dayLabel(DateTime date) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[date.weekday - 1];
  }

  static String _monthLabel(DateTime date) {
    const monthNames = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return monthNames[date.month - 1];
  }
}
