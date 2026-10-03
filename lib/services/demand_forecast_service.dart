import 'market_demand_service.dart';

/// Demand Forecast: the expected demand for each commodity in a chosen
/// *future* month, estimated from the marketplace's own completed-order
/// history (`market_sales`, the same anonymized record Best-Selling
/// Products uses). Nothing here is a fixed or hand-assigned label, and
/// commodities come from the Admin-managed list, so a new one is forecast
/// as soon as it has enough completed orders.
///
/// How a commodity's forecast is worked out:
///  1. Recent demand — its completed orders per month over the last 90
///     days. This is the base: actual purchases, the strongest signal.
///  2. Recent trend — the last 30 days against the 30 before. More than
///     10% up is Rising, more than 10% down is Declining. The base is
///     nudged in that direction (by at most 25%).
///  3. Season — only when there is a full year of history: how the same
///     calendar month a year earlier compared with that commodity's
///     average month. Applied as a multiplier (between half and double).
///  4. Demand level — each commodity's expected orders against the
///     highest one: two-thirds or more is High, one-third or more is
///     Moderate, otherwise Low.
///
/// Confidence says how much history is behind it, and a commodity with too
/// little is left out rather than guessed. Views, searches and pending
/// orders are not used.

enum ForecastConfidence { high, moderate, limited }

class CommodityForecast {
  final String commodity;
  final String category;
  final DemandLevel demand;
  final DemandTrend trend;

  /// Where its recent completed orders came from, busiest first (up to 3).
  final List<String> topAreas;

  /// Only set when one order type clearly dominates recent orders.
  final bool? mostlyWholesale;
  final ForecastConfidence confidence;

  /// What the forecast rests on, for the Admin's "data availability".
  final int historyOrders;
  final int historyMonths;

  /// Whether the same month of the previous year was available to
  /// account for season.
  final bool seasonal;

  const CommodityForecast({
    required this.commodity,
    required this.category,
    required this.demand,
    required this.trend,
    required this.topAreas,
    required this.mostlyWholesale,
    required this.confidence,
    required this.historyOrders,
    required this.historyMonths,
    required this.seasonal,
  });
}

class DemandForecast {
  final DateTime month;

  /// Ranked, highest expected demand first. Empty when [insufficient].
  final List<CommodityForecast> items;

  /// There isn't enough completed-order history to forecast anything
  /// reliably — the UI says so instead of showing a made-up ranking.
  final bool insufficient;

  const DemandForecast({
    required this.month,
    required this.items,
    required this.insufficient,
  });
}

class DemandForecastService {
  const DemandForecastService._();

  /// Fewer completed orders than this across the whole marketplace and no
  /// forecast is offered at all.
  static const int minMarketplaceOrders = 10;

  /// Fewer than this for one commodity and it is left out.
  static const int minCommodityOrders = 3;

  static const Duration _recentWindow = Duration(days: 90);
  static const Duration _trendWindow = Duration(days: 30);

  /// The month after [now] — what the Farmer Dashboard shows by default.
  static DateTime nextMonth([DateTime? now]) {
    final today = now ?? DateTime.now();
    return DateTime(today.year, today.month + 1);
  }

  /// The next [count] months that can be forecast, soonest first.
  static List<DateTime> upcomingMonths(int count, [DateTime? now]) {
    final today = now ?? DateTime.now();
    return [
      for (var i = 1; i <= count; i++) DateTime(today.year, today.month + i),
    ];
  }

  static bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  static DemandForecast forecast({
    required Iterable<Map<String, dynamic>> sales,
    required DateTime month,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    // Only what has already happened counts as history.
    final all = MarketDemandService.parseSales(
      sales,
    ).where((s) => !s.date.isAfter(today)).toList();
    final target = DateTime(month.year, month.month);
    if (all.length < minMarketplaceOrders) {
      return DemandForecast(month: target, items: const [], insufficient: true);
    }

    final recentStart = today.subtract(_recentWindow);
    final trendStart = today.subtract(_trendWindow);
    final previousTrendStart = trendStart.subtract(_trendWindow);
    final sameMonthLastYear = DateTime(target.year - 1, target.month);
    final monthsAhead =
        (target.year - today.year) * 12 + target.month - today.month;

    final byCommodity = <String, List<MarketSale>>{};
    for (final sale in all) {
      byCommodity.putIfAbsent(sale.commodity.toLowerCase(), () => []).add(sale);
    }

    final scored = <(double, CommodityForecast)>[];
    for (final orders in byCommodity.values) {
      if (orders.length < minCommodityOrders) continue;
      orders.sort((a, b) => a.date.compareTo(b.date));
      final first = orders.first.date;

      // 1. Recent demand, per 30 days — over the part of the last 90 days
      // this commodity has actually been selling for.
      final recent = orders.where((s) => s.date.isAfter(recentStart)).toList();
      final activeDays = today
          .difference(first.isAfter(recentStart) ? first : recentStart)
          .inDays
          .clamp(30, _recentWindow.inDays);
      final monthlyRate = recent.length * 30 / activeDays;

      // 2. Recent trend.
      final last30 = orders.where((s) => s.date.isAfter(trendStart)).length;
      final prior30 = orders
          .where(
            (s) =>
                s.date.isAfter(previousTrendStart) &&
                !s.date.isAfter(trendStart),
          )
          .length;
      final double change;
      if (prior30 > 0) {
        change = (last30 - prior30) / prior30;
      } else if (last30 == 0 || first.isAfter(previousTrendStart)) {
        // Quiet in both periods, or too new to have an earlier period to
        // compare with: no trend to read.
        change = 0;
      } else {
        change = 1; // Selling again after a quiet month.
      }
      final trend = change > 0.10
          ? DemandTrend.rising
          : change < -0.10
          ? DemandTrend.declining
          : DemandTrend.stable;
      final trendFactor = (1 + change * 0.5).clamp(0.75, 1.25);

      // 3. Season — needs the same month a year earlier, inside a full
      // year of this commodity's history.
      final yearStart = DateTime(target.year - 1, target.month - 6);
      final yearEnd = DateTime(target.year - 1, target.month + 6);
      final hasYear = !first.isAfter(yearStart) && !yearEnd.isAfter(today);
      var seasonFactor = 1.0;
      if (hasYear) {
        final yearOrders = orders
            .where(
              (s) => !s.date.isBefore(yearStart) && s.date.isBefore(yearEnd),
            )
            .length;
        final thatMonth = orders
            .where((s) => _inMonth(s.date, sameMonthLastYear))
            .length;
        if (yearOrders > 0) {
          seasonFactor = (thatMonth / (yearOrders / 12)).clamp(0.5, 2.0);
        }
      }

      final expected = monthlyRate * trendFactor * seasonFactor;
      if (expected <= 0) continue; // Nothing recent to project from.

      // Confidence: how much real history is behind it.
      final months = {
        for (final s in orders) s.date.year * 12 + s.date.month,
      }.length;
      var confidence = orders.length >= 30 && months >= 6 && hasYear
          ? ForecastConfidence.high
          : orders.length >= 10 && months >= 3
          ? ForecastConfidence.moderate
          : ForecastConfidence.limited;
      // Far ahead with no seasonal history to lean on: don't claim much.
      if (monthsAhead > 3 && !hasYear) confidence = ForecastConfidence.limited;

      final basis = recent.isEmpty ? orders : recent;
      final typed = basis.where((s) => s.wholesale != null).toList();
      final wholesale = typed.where((s) => s.wholesale!).length;
      final wholesaleShare = typed.isEmpty ? 0.0 : wholesale / typed.length;

      scored.add((
        expected,
        CommodityForecast(
          commodity: orders.last.commodity,
          category: orders.last.category,
          // Filled in below, once the top expected demand is known.
          demand: DemandLevel.low,
          trend: trend,
          topAreas: _topAreas(basis),
          mostlyWholesale: typed.length < 5
              ? null
              : wholesaleShare >= 0.6
              ? true
              : wholesaleShare <= 0.4
              ? false
              : null,
          confidence: confidence,
          historyOrders: orders.length,
          historyMonths: months,
          seasonal: hasYear,
        ),
      ));
    }

    if (scored.isEmpty) {
      return DemandForecast(month: target, items: const [], insufficient: true);
    }
    scored.sort((a, b) {
      final byExpected = b.$1.compareTo(a.$1);
      return byExpected != 0
          ? byExpected
          : a.$2.commodity.compareTo(b.$2.commodity);
    });
    final top = scored.first.$1;

    return DemandForecast(
      month: target,
      insufficient: false,
      items: [
        for (final (expected, item) in scored)
          CommodityForecast(
            commodity: item.commodity,
            category: item.category,
            demand: expected / top >= 2 / 3
                ? DemandLevel.high
                : expected / top >= 1 / 3
                ? DemandLevel.moderate
                : DemandLevel.low,
            trend: item.trend,
            topAreas: item.topAreas,
            mostlyWholesale: item.mostlyWholesale,
            confidence: item.confidence,
            historyOrders: item.historyOrders,
            historyMonths: item.historyMonths,
            seasonal: item.seasonal,
          ),
      ],
    );
  }

  static List<String> _topAreas(Iterable<MarketSale> sales) {
    final counts = <String, int>{};
    for (final sale in sales) {
      if (sale.area.isNotEmpty) {
        counts[sale.area] = (counts[sale.area] ?? 0) + 1;
      }
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byOrders = b.value.compareTo(a.value);
        return byOrders != 0 ? byOrders : a.key.compareTo(b.key);
      });
    return [for (final entry in ranked.take(3)) entry.key];
  }
}
