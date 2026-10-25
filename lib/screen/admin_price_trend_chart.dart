import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/historical_demand_service.dart';
import '../services/market_price_helpers.dart';
import '../services/price_trend_service.dart';
import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminRadii, AdminThemeScope;
import 'admin_filter_controls.dart' show kAdminFontFamily;
import 'admin_overview_widgets.dart'
    show adminAxisTop, adminCompactPeso, adminGreenAt, adminLegendDot;

/// Market Trends → Price Trend: [commodity]'s average price per month, the
/// previous year against the current one, as two lines (see
/// [PriceTrendService] for which prices count). The Admin picks the pair of
/// years, starting from 2025 against 2026.
class AdminPriceTrendChart extends StatefulWidget {
  final String commodity;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> completedOrders;
  final List<HistoricalDemandRecord> historical;

  const AdminPriceTrendChart({
    super.key,
    required this.commodity,
    required this.products,
    required this.completedOrders,
    required this.historical,
  });

  @override
  State<AdminPriceTrendChart> createState() => _AdminPriceTrendChartState();
}

class _AdminPriceTrendChartState extends State<AdminPriceTrendChart> {
  late ({int previous, int current}) _years = PriceTrendService.yearPairs(
    DateTime.now(),
  ).last;

  late Stream<List<Map<String, dynamic>>> _reference = _referenceHistory();

  @override
  void didUpdateWidget(AdminPriceTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commodity != widget.commodity) {
      _reference = _referenceHistory();
    }
  }

  // The commodity's dated reference prices from Price Management. Its
  // `market_prices` document is found by the name stored in it, since an
  // older document's id need not follow the name.
  Stream<List<Map<String, dynamic>>> _referenceHistory() async* {
    final commodity = widget.commodity.trim().toLowerCase();
    final prices = await FirebaseFirestore.instance
        .collection('market_prices')
        .get();
    final matches = prices.docs.where(
      (doc) =>
          (doc.data()['name'] ?? '').toString().trim().toLowerCase() ==
          commodity,
    );
    if (matches.isEmpty) {
      yield const [];
      return;
    }
    yield* matches.first.reference
        .collection('history')
        .snapshots()
        .map((snap) => [for (final doc in snap.docs) doc.data()]);
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _reference,
      builder: (context, reference) {
        final points = PriceTrendService.collect(
          commodity: widget.commodity,
          products: widget.products,
          completedOrders: widget.completedOrders,
          referenceHistory: reference.data ?? const [],
          historical: widget.historical,
        );
        return _content(
          c,
          points,
          referenceMissing: reference.hasError,
          referenceLoading: !reference.hasData && !reference.hasError,
        );
      },
    );
  }

  Widget _content(
    AdminPalette c,
    List<PriceTrendPoint> points, {
    required bool referenceMissing,
    required bool referenceLoading,
  }) {
    final unit = unitForCommodity(widget.commodity);
    final previous = PriceTrendService.monthlyAverages(points, _years.previous);
    final current = PriceTrendService.monthlyAverages(points, _years.current);
    final hasData = [...previous, ...current].any((v) => v != null);
    final previousColor = c.blue;
    final currentColor = adminGreenAt(c, 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Price Trend',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Average ${widget.commodity} price per $unit, month by '
                  'month — from farmer listings and sales, and Admin '
                  'reference and imported prices',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
            _yearPicker(c),
          ],
        ),
        const SizedBox(height: 14),
        if (referenceMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: c.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reference prices from Price Management could not be '
                    'loaded, so they are not included here.',
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        if (!hasData && !referenceLoading)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AdminRadii.card),
            ),
            child: Text(
              'No ${widget.commodity} prices on record for '
              '${_years.previous} or ${_years.current} yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          )
        else ...[
          SizedBox(
            height: 260,
            child: _chart(
              c,
              unit: unit,
              previous: previous,
              current: current,
              previousColor: previousColor,
              currentColor: currentColor,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _legend(c, previousColor, '${_years.previous}'),
                _legend(c, currentColor, '${_years.current}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _summary(c, points, unit, previous, current),
        ],
      ],
    );
  }

  // "2025 vs 2026", opening the pairs from 2025 against 2026 onward.
  Widget _yearPicker(AdminPalette c) {
    String label(({int previous, int current}) pair) =>
        '${pair.previous} vs ${pair.current}';
    final pairs = PriceTrendService.yearPairs(DateTime.now());
    return PopupMenuButton<({int previous, int current})>(
      tooltip: 'Years to compare',
      color: c.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
      onSelected: (pair) => setState(() => _years = pair),
      itemBuilder: (context) => [
        for (final pair in pairs.reversed)
          PopupMenuItem(
            value: pair,
            height: 38,
            child: Text(
              label(pair),
              style: TextStyle(
                fontSize: 13,
                fontWeight: pair == _years ? FontWeight.w600 : FontWeight.w500,
                color: pair == _years ? c.green : c.textPrimary,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AdminRadii.pill),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_outlined, size: 15, color: c.textSecondary),
            const SizedBox(width: 6),
            Text(
              label(_years),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: c.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _legend(AdminPalette c, Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      adminLegendDot(color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
    ],
  );

  Widget _chart(
    AdminPalette c, {
    required String unit,
    required List<double?> previous,
    required List<double?> current,
    required Color previousColor,
    required Color currentColor,
  }) {
    final highest = [
      ...previous,
      ...current,
    ].whereType<double>().fold<double>(0, math.max);
    final top = adminAxisTop(highest * 1.1);
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 11);

    // A month with no price is a gap in its line, never a zero.
    List<FlSpot> spots(List<double?> monthly) => [
      for (var m = 0; m < 12; m++)
        monthly[m] == null
            ? FlSpot.nullSpot
            : FlSpot(m.toDouble(), monthly[m]!),
    ];

    LineChartBarData line(List<double?> monthly, Color color) =>
        LineChartBarData(
          spots: spots(monthly),
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3.5,
              color: color,
              strokeWidth: 2,
              strokeColor: c.surface,
            ),
          ),
        );

    final bars = [line(previous, previousColor), line(current, currentColor)];
    final years = [_years.previous, _years.current];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 11,
        minY: 0,
        maxY: top,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          verticalInterval: 1,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 1),
          getDrawingVerticalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 1, dashArray: const [3, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: top / 4,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  adminCompactPeso(value),
                  textAlign: TextAlign.right,
                  style: axisStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final m = value.toInt();
                if (value != m || m < 0 || m > 11) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM').format(DateTime(2000, m + 1)),
                    style: axisStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.textPrimary,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${DateFormat('MMM').format(DateTime(2000, spot.x.toInt() + 1))} '
                  '${years[spot.barIndex]}: ${formatPeso(spot.y)}/$unit',
                  TextStyle(
                    fontFamily: kAdminFontFamily,
                    color: spot.barIndex == 0
                        ? Color.lerp(previousColor, Colors.white, 0.45)
                        : Color.lerp(currentColor, Colors.white, 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: bars,
      ),
    );
  }

  // Each year's average, the change between them, and what the figures
  // rest on.
  Widget _summary(
    AdminPalette c,
    List<PriceTrendPoint> points,
    String unit,
    List<double?> previous,
    List<double?> current,
  ) {
    final previousAverage = PriceTrendService.yearAverage(previous);
    final currentAverage = PriceTrendService.yearAverage(current);
    String average(int year, double? value) => value == null
        ? '$year: no prices'
        : '$year average ${formatPeso(value)}/$unit';
    var change = '';
    if (previousAverage != null && currentAverage != null) {
      final percent =
          (currentAverage - previousAverage) / previousAverage * 100;
      change = percent.abs() < 0.5
          ? ' · about the same'
          : ' · ${percent > 0 ? 'up' : 'down'} '
                '${percent.abs().toStringAsFixed(1)}%';
    }

    final inYears = points.where(
      (p) => p.date.year == _years.previous || p.date.year == _years.current,
    );
    int count(PriceTrendSource source) =>
        inYears.where((p) => p.source == source).length;
    String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final basis = [
      part(
        count(PriceTrendSource.farmerListing),
        'farmer listing',
        'farmer listings',
      ),
      part(
        count(PriceTrendSource.farmerSale),
        'completed sale',
        'completed sales',
      ),
      part(
        count(PriceTrendSource.adminReference),
        'Admin reference price',
        'Admin reference prices',
      ),
      part(
        count(PriceTrendSource.adminImport),
        'imported record',
        'imported records',
      ),
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${average(_years.previous, previousAverage)} · '
          '${average(_years.current, currentAverage)}$change',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Based on $basis. Retail prices in $unit only; each counts in the '
          'month of its own date.',
          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
        ),
      ],
    );
  }
}
