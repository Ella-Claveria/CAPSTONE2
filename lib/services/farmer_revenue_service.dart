import 'package:cloud_firestore/cloud_firestore.dart';

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

  static String seasonLabel(DateTime now) {
    final month = now.month;
    if (month >= 6 && month <= 11) return 'Rainy season';
    return 'Dry season';
  }

  static Map<String, dynamic> marketObjective({
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> orders,
    required DateTime now,
  }) {
    final completedOrders = orders.where((order) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (status != 'completed') return false;
      final createdAt = _toDateTime(order['createdAt']);
      if (createdAt == null) return false;
      final daysAgo = now.difference(createdAt).inDays;
      return daysAgo <= 365;
    }).toList();

    final seasonOrders = completedOrders.where((order) {
      final createdAt = _toDateTime(order['createdAt']);
      if (createdAt == null) return false;
      final month = createdAt.month;
      if (month >= 6 && month <= 11) return seasonLabel(now) == 'Rainy season';
      return seasonLabel(now) == 'Dry season';
    }).toList();

    final seasonalCounts = <String, int>{};
    for (final order in seasonOrders) {
      final name = (order['productName'] ?? order['name'] ?? '').toString();
      if (name.trim().isEmpty) continue;
      seasonalCounts[name] = (seasonalCounts[name] ?? 0) + 1;
    }

    final marketplaceCounts = <String, int>{};
    for (final order in completedOrders) {
      final name = (order['productName'] ?? order['name'] ?? '').toString();
      if (name.trim().isEmpty) continue;
      marketplaceCounts[name] = (marketplaceCounts[name] ?? 0) + 1;
    }

    final fallbackProductCounts = <String, int>{};
    for (final product in products) {
      final name = (product['name'] ?? '').toString();
      if (name.isEmpty) continue;
      fallbackProductCounts[name] = (fallbackProductCounts[name] ?? 0) + 1;
    }

    String seasonalPick = 'Vegetables';
    double seasonalShare = 0;
    if (seasonalCounts.isNotEmpty) {
      final top = seasonalCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      seasonalPick = top.key;
      final total = seasonalCounts.values.reduce((a, b) => a + b);
      seasonalShare = total == 0 ? 0 : top.value / total;
    } else if (fallbackProductCounts.isNotEmpty) {
      final top = fallbackProductCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      seasonalPick = top.key;
      final total = fallbackProductCounts.values.reduce((a, b) => a + b);
      seasonalShare = total == 0 ? 0 : top.value / total;
    }

    String demandPick = 'Vegetables';
    double marketShare = 0;
    if (marketplaceCounts.isNotEmpty) {
      final top = marketplaceCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      demandPick = top.key;
      final total = marketplaceCounts.values.reduce((a, b) => a + b);
      marketShare = total == 0 ? 0 : top.value / total;
    } else if (fallbackProductCounts.isNotEmpty) {
      final top = fallbackProductCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      demandPick = top.key;
      final total = fallbackProductCounts.values.reduce((a, b) => a + b);
      marketShare = total == 0 ? 0 : top.value / total;
    }

    double averagePrice = 0;
    final validPrices = products
        .map((product) {
          final raw = product['price'];
          if (raw is num) return raw.toDouble();
          return num.tryParse(raw?.toString() ?? '')?.toDouble() ?? 0.0;
        })
        .where((value) => value > 0)
        .toList();

    if (validPrices.isNotEmpty) {
      averagePrice = validPrices.reduce((a, b) => a + b) / validPrices.length;
    }

    return {
      'season': seasonLabel(now),
      'seasonalPick': seasonalPick,
      'marketPick': demandPick,
      'marketAverage': averagePrice,
      'seasonalShare': seasonalShare,
      'marketShare': marketShare,
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
