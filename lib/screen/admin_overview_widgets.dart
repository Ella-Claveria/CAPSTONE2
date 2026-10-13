import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_analytics_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/shimmer.dart';
import 'admin_filter_controls.dart';
import 'admin_dashboard_screen.dart'
    show AdminThemeScope, AdminPalette, AdminRadii;

// ============================================================
// The top of the Admin Analytics Dashboard: the Overview summary strip and
// the two Sales Performance charts. One green accent throughout, in
// lighter and darker steps, on neutral surfaces with thin borders.
//
// Every widget here shows only what it is handed or computes from real
// orders — nothing is sampled, padded or estimated. A period with no
// completed sales shows an empty state, never a chart of zeros.
// ============================================================

/// The portal's green at strength [t]: 0 is the palest step, 1 the
/// strongest. Used for bars and donut slices so that "more" reads darker.
Color adminGreenAt(AdminPalette c, double t) {
  final pale = Color.lerp(c.green, c.surface, 0.68)!;
  final strong = c.isDark ? c.green : Color.lerp(c.green, Colors.black, 0.28)!;
  return Color.lerp(pale, strong, t.clamp(0.0, 1.0))!;
}

/// One figure of the Overview strip.
class AdminOverviewItem {
  final String label;
  final IconData icon;

  /// Null while the figure is still loading.
  final String? value;
  final String caption;

  /// The figure could not be loaded (shown as a dash, never as zero).
  final bool failed;

  /// Something waiting on the Admin: its card is tinted amber, not green.
  final bool attention;

  /// Opens the page the figure comes from; null for a card that is not
  /// clickable.
  final VoidCallback? onTap;

  const AdminOverviewItem({
    required this.label,
    required this.icon,
    required this.value,
    required this.caption,
    this.failed = false,
    this.attention = false,
    this.onTap,
  });
}

/// The Overview: each figure on its own lightly tinted card, side by side
/// and equal in width and height. Wraps to two per row, then one, on
/// narrower windows.
class AdminOverviewStrip extends StatelessWidget {
  final List<AdminOverviewItem> items;
  const AdminOverviewStrip({super.key, required this.items});

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? items.length : (width >= 520 ? 2 : 1);
        final rows = <List<AdminOverviewItem>>[
          for (var i = 0; i < items.length; i += columns)
            items.sublist(i, math.min(i + columns, items.length)),
        ];
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(
                        child: i < rows[r].length
                            ? _card(c, rows[r][i])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _card(AdminPalette c, AdminOverviewItem item) {
    final tint = item.attention ? c.amber : c.green;
    final radius = BorderRadius.circular(14);
    // Material + InkWell, so a clickable card shows the pointer, a hover
    // tint and a ripple inside its own rounded shape.
    return Material(
      color: Color.alphaBlend(
        tint.withValues(alpha: c.isDark ? 0.10 : 0.06),
        c.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: Color.alphaBlend(tint.withValues(alpha: 0.16), c.border),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        hoverColor: tint.withValues(alpha: 0.07),
        splashColor: tint.withValues(alpha: 0.12),
        child: _OverviewSegment(item: item),
      ),
    );
  }
}

class _OverviewSegment extends StatelessWidget {
  final AdminOverviewItem item;
  const _OverviewSegment({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final loading = item.value == null;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.attention ? c.amberBg : c.greenBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: item.attention ? c.amber : c.green,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                // Same line heights loading or loaded, so nothing shifts.
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: loading
                        ? Shimmer(
                            baseColor: c.surfaceAlt,
                            highlightColor: c.border,
                            child: bar(72, 20),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item.value!,
                              style: TextStyle(
                                color: item.failed
                                    ? c.textMuted
                                    : c.textPrimary,
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading ? ' ' : item.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Last 6 Months" period filter on a chart card.
class AdminPeriodDropdown extends StatelessWidget {
  final int months;
  final ValueChanged<int> onChanged;
  const AdminPeriodDropdown({
    super.key,
    required this.months,
    required this.onChanged,
  });

  static const List<int> options = [3, 6, 12];
  static const int initial = 6;

  static String label(int months) => 'Last $months Months';

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return PopupMenuButton<int>(
      tooltip: 'Period',
      color: c.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<int>(
            value: option,
            height: 38,
            child: Text(
              label(option),
              style: TextStyle(
                fontSize: 13,
                fontWeight: option == months
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: option == months ? c.green : c.textPrimary,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AdminRadii.pill),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label(months),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 18, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// The shell every analytics card shares — same padding, header and body
/// height — so they stay the same size next to each other.
class AdminChartCard extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Optional control at the right of the header (a filter, a search).
  final Widget? trailing;
  final Widget child;

  /// Height of the area under the header; equal on cards that sit side
  /// by side.
  final double bodyHeight;

  const AdminChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.child,
    this.bodyHeight = 264,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: bodyHeight, child: child),
        ],
      ),
    );
  }
}

class AdminChartEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  const AdminChartEmpty({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.greenBg,
              borderRadius: BorderRadius.circular(AdminRadii.card),
            ),
            child: Icon(icon, size: 26, color: c.green),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget adminLegendDot(Color color) => Container(
  width: 10,
  height: 10,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(3),
  ),
);

// "₱20k", "₱1.5M" — axis labels only; exact figures use formatPeso.
String _compactPeso(double value) {
  String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (value >= 1000000) return '₱${trim(value / 1000000)}M';
  if (value >= 1000) return '₱${trim(value / 1000)}k';
  return '₱${trim(value)}';
}

// The next "round" number at or above [value] that divides into 4 even
// steps, for the top of the value axis.
double _axisTop(double value) {
  if (value <= 0) return 4;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final fraction = value / magnitude;
  for (final step in const [1.0, 2.0, 4.0, 5.0, 8.0, 10.0]) {
    if (fraction <= step) return step * magnitude;
  }
  return 10 * magnitude;
}

/// SALES PERFORMANCE — revenue of completed orders, one bar per calendar
/// month of the selected period (see
/// [DashboardAnalyticsService.monthlyCompletedSales]).
class AdminSalesPerformanceCard extends StatefulWidget {
  /// Every order; only the completed ones are counted.
  final List<Map<String, dynamic>> orders;
  const AdminSalesPerformanceCard({super.key, required this.orders});

  @override
  State<AdminSalesPerformanceCard> createState() =>
      _AdminSalesPerformanceCardState();
}

class _AdminSalesPerformanceCardState extends State<AdminSalesPerformanceCard> {
  int _months = AdminPeriodDropdown.initial;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final sales = DashboardAnalyticsService.monthlyCompletedSales(
      widget.orders,
      now: DateTime.now(),
      months: _months,
    );
    final total = sales.fold<double>(0, (sum, m) => sum + m.revenue);
    final orderCount = sales.fold<int>(0, (sum, m) => sum + m.orders);
    final highest = sales.fold<double>(0, (m, s) => math.max(m, s.revenue));

    return AdminChartCard(
      title: 'Sales Performance',
      subtitle: 'Monthly sales from completed orders',
      trailing: AdminPeriodDropdown(
        months: _months,
        onChanged: (months) => setState(() => _months = months),
      ),
      child: total <= 0
          ? const AdminChartEmpty(
              icon: Icons.show_chart_rounded,
              message:
                  'No completed sales data available for the selected '
                  'period yet.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatPeso(total),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$orderCount completed '
                        '${orderCount == 1 ? 'order' : 'orders'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(child: _chart(c, sales, highest)),
                const SizedBox(height: 10),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      adminLegendDot(adminGreenAt(c, 1)),
                      const SizedBox(width: 6),
                      Text(
                        'Total Sales (₱)',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _chart(
    AdminPalette c,
    List<({DateTime month, double revenue, int orders})> sales,
    double highest,
  ) {
    final top = _axisTop(highest);
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 11);
    final now = DateTime.now();
    final spansYears = sales.first.month.year != sales.last.month.year;

    final line = adminGreenAt(c, 1);

    // An area line: each month a point, joined and filled underneath, so
    // the rise and fall across the period reads at a glance.
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: top,
        minX: 0,
        maxX: (sales.length - 1).toDouble(),
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
                  _compactPeso(value),
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
                final i = value.toInt();
                // Whole months only — never a label between two points.
                if (value != i || i < 0 || i >= sales.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM').format(sales[i].month),
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
            getTooltipItems: (spots) => [
              for (final spot in spots)
                () {
                  final m = sales[spot.x.toInt()];
                  final sameYear = !spansYears && m.month.year == now.year;
                  return LineTooltipItem(
                    '${DateFormat(sameYear ? 'MMMM' : 'MMMM y').format(m.month)}\n'
                    '${formatPeso(m.revenue)} · ${m.orders} '
                    '${m.orders == 1 ? 'order' : 'orders'}',
                    TextStyle(
                      fontFamily: kAdminFontFamily,
                      color: c.surface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }(),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < sales.length; i++)
                FlSpot(i.toDouble(), sales[i].revenue),
            ],
            isCurved: true,
            // Keeps the curve from dipping below a month's real value.
            preventCurveOverShooting: true,
            color: line,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 4,
                color: line,
                strokeWidth: 2,
                strokeColor: c.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  line.withValues(alpha: 0.32),
                  line.withValues(alpha: 0.04),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SALES BY CATEGORY — what buyers actually purchased: completed-order
/// revenue in the selected period, grouped by the product's commodity
/// category (see [DashboardAnalyticsService.categoryRevenue]).
class AdminSalesByCategoryCard extends StatefulWidget {
  /// Completed-order revenue per category for the last N calendar months.
  final Map<String, num> Function(int months) revenueFor;
  const AdminSalesByCategoryCard({super.key, required this.revenueFor});

  @override
  State<AdminSalesByCategoryCard> createState() =>
      _AdminSalesByCategoryCardState();
}

class _AdminSalesByCategoryCardState extends State<AdminSalesByCategoryCard> {
  int _months = AdminPeriodDropdown.initial;

  // Beyond this many categories the smallest are shown together as "Other".
  static const int _maxSlices = 7;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final sorted =
        widget
            .revenueFor(_months)
            .entries
            .where((e) => e.value > 0)
            .map((e) => (name: e.key, value: e.value.toDouble()))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);

    var slices = sorted;
    if (sorted.length > _maxSlices) {
      final rest = sorted.sublist(_maxSlices - 1);
      slices = [
        ...sorted.take(_maxSlices - 1),
        (name: 'Other', value: rest.fold<double>(0, (sum, e) => sum + e.value)),
      ];
    }
    // Largest share strongest, down to the palest.
    Color colorOf(int i) =>
        adminGreenAt(c, slices.length == 1 ? 1 : 1 - i / (slices.length - 1));

    return AdminChartCard(
      title: 'Sales by Category',
      subtitle: 'Completed purchases by commodity category',
      trailing: AdminPeriodDropdown(
        months: _months,
        onChanged: (months) => setState(() => _months = months),
      ),
      child: slices.isEmpty
          ? const AdminChartEmpty(
              icon: Icons.pie_chart_outline_rounded,
              message:
                  'No completed category sales data available for the '
                  'selected period.',
            )
          : Row(
              children: [
                SizedBox(
                  width: 172,
                  height: 172,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          centerSpaceRadius: 56,
                          sectionsSpace: 2,
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                value: slices[i].value,
                                color: colorOf(i),
                                radius: 28,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatPeso(total),
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total Sales',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < slices.length; i++)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                          child: Row(
                            children: [
                              adminLegendDot(colorOf(i)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  slices[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _share(slices[i].value, total),
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _share(double value, double total) {
    if (total <= 0) return '0%';
    final percent = value / total * 100;
    if (percent > 0 && percent < 1) return '<1%';
    return '${percent.round()}%';
  }
}

/// A chart card that has not loaded yet: the same box, padding and height
/// as [AdminChartCard], with shimmering bars where the title and the chart
/// will be — so the section is in place at once and nothing shifts when
/// the real card replaces it.
class AdminChartCardSkeleton extends StatelessWidget {
  final double bodyHeight;
  const AdminChartCardSkeleton({super.key, this.bodyHeight = 264});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    Widget bar(double? width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      // The shimmer only covers the bars, not the card around them.
      child: Shimmer(
        baseColor: c.surfaceAlt,
        highlightColor: c.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same height as the real header: a 16px title and a 12.5px
            // subtitle with 3px between them.
            SizedBox(
              height: 38,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [bar(170, 16), bar(240, 12)],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: bodyHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bar(120, 18),
                  const SizedBox(height: 16),
                  Expanded(child: bar(null, double.infinity)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
