import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import 'admin_dashboard_screen.dart'
    show AdminThemeScope, AdminPalette, AdminEmptyState, AdminRadii;
import 'admin_overview_widgets.dart'
    show AdminChartCard, AdminChartEmpty, adminGreenAt;

// ============================================================
// New chart widgets for the Admin Analytics Dashboard redesign. Every
// widget here takes already-computed, real data (no mock/sample values
// anywhere) — the Firestore reads and aggregation live in
// admin_dashboard_screen.dart, which passes plain typed data down so
// this file stays decoupled from its private helper types.
// ============================================================

// The two Market Intelligence cards share this body height, so they stay
// the same size side by side.
const double _marketCardBodyHeight = 288;

// ---- Top-Selling Products (ranked horizontal bars, top 5) ----
/// What buyers actually bought most: products ranked by the revenue of
/// their completed orders, with the quantity sold. Ranked by revenue
/// rather than quantity because quantities come in different units (kg,
/// pieces, heads) and cannot be compared with each other.
class AdminTopProductsCard extends StatelessWidget {
  final List<({String name, num revenue, num quantity})> products;
  const AdminTopProductsCard({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final maxRevenue = products.fold<double>(
      0,
      (max, p) => p.revenue > max ? p.revenue.toDouble() : max,
    );

    return AdminChartCard(
      title: 'Top-Selling Products',
      subtitle: 'Ranked by sales value of completed orders',
      bodyHeight: _marketCardBodyHeight,
      child: products.isEmpty
          ? const AdminChartEmpty(
              icon: Icons.emoji_events_outlined,
              message: 'No completed sales data available yet.',
            )
          : Column(
              children: [
                for (var i = 0; i < products.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _row(c, i, products[i], maxRevenue),
                ],
              ],
            ),
    );
  }

  Widget _row(
    AdminPalette c,
    int index,
    ({String name, num revenue, num quantity}) p,
    double maxRevenue,
  ) {
    final isTop = index == 0;
    final barValue = maxRevenue <= 0
        ? 0.0
        : (p.revenue / maxRevenue).clamp(0.03, 1.0);
    // The same green steps as the charts above: strongest for #1.
    final strength = products.length == 1
        ? 1.0
        : 1 - index / (products.length - 1) * 0.75;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isTop ? adminGreenAt(c, 1) : c.greenBg,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: isTop ? Colors.white : c.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPeso(p.revenue),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: barValue,
                  minHeight: 6,
                  backgroundColor: c.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(adminGreenAt(c, strength)),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${formatStock(p.quantity, unitForProductName(p.name))} sold',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The commodities whose name has a word starting with [query] — "ch"
/// finds Chicken, "co" finds Coconut and Corn — names that start with it
/// first. An empty query returns them all.
List<String> matchCommodities(Iterable<String> names, String query) {
  final q = query.trim().toLowerCase();
  final sorted = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (q.isEmpty) return sorted;
  final starts = <String>[];
  final wordStarts = <String>[];
  for (final name in sorted) {
    final lower = name.toLowerCase();
    if (lower.startsWith(q)) {
      starts.add(name);
    } else if (lower.split(RegExp(r'[\s/()-]+')).any((w) => w.startsWith(q))) {
      wordStarts.add(name);
    }
  }
  return [...starts, ...wordStarts];
}

// ---- Price Trend vs. Baseline (line chart + commodity search) ----
/// One commodity's weekly average price in completed buyer orders, against
/// the Admin's baseline (reference) price for that same commodity.
///
/// The commodity is chosen from a search field that suggests matches from
/// the supported commodity list as the admin types.
class AdminPriceTrendCard extends StatefulWidget {
  /// The supported commodities offered by the search.
  final List<String> commodities;

  /// Admin baseline price per commodity; a commodity without one is absent.
  final Map<String, double> baselineByCommodity;

  /// Weekly average completed-order price per commodity, oldest first;
  /// null for a week with no completed order.
  final Map<String, List<double?>> weeklyPricesByCommodity;

  const AdminPriceTrendCard({
    super.key,
    required this.commodities,
    required this.baselineByCommodity,
    required this.weeklyPricesByCommodity,
  });

  @override
  State<AdminPriceTrendCard> createState() => _AdminPriceTrendCardState();
}

class _AdminPriceTrendCardState extends State<AdminPriceTrendCard> {
  String? _selected;

  bool _hasSales(String name) =>
      (widget.weeklyPricesByCommodity[name] ?? const []).any((v) => v != null);

  // Opens on a commodity that has sales to show, when there is one.
  String? _initial(List<String> names) {
    if (names.isEmpty) return null;
    for (final name in names) {
      if (_hasSales(name)) return name;
    }
    return names.first;
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final names = matchCommodities(widget.commodities, '');
    if (_selected == null || !names.contains(_selected)) {
      _selected = _initial(names);
    }
    final selected = _selected;

    final weekly = selected == null
        ? const <double?>[]
        : (widget.weeklyPricesByCommodity[selected] ?? const <double?>[]);
    final baseline = selected == null
        ? null
        : widget.baselineByCommodity[selected];
    final hasData = weekly.any((v) => v != null);
    final latest = weekly.lastWhere((v) => v != null, orElse: () => null);

    return AdminChartCard(
      title: 'Price Trend vs. Baseline',
      subtitle: 'Weekly average price in completed orders',
      bodyHeight: _marketCardBodyHeight,
      trailing: names.isEmpty
          ? null
          : AdminCommoditySearchField(
              // Rebuilt when the selection changes, so the field shows it.
              key: ValueKey(selected),
              commodities: names,
              selected: selected,
              onSelected: (name) => setState(() => _selected = name),
            ),
      child: selected == null
          ? const AdminChartEmpty(
              icon: Icons.show_chart,
              message: 'No supported commodities to show yet.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summary(c, selected, baseline, latest),
                const SizedBox(height: 14),
                Expanded(
                  child: hasData
                      ? LineChart(_chartData(c, weekly, baseline))
                      : const AdminChartEmpty(
                          icon: Icons.show_chart,
                          message:
                              'No completed sales data available yet for '
                              'this commodity.',
                        ),
                ),
              ],
            ),
    );
  }

  // The selected commodity, with its two reference figures. The baseline
  // is shown whenever the Admin has set one, sales or not.
  Widget _summary(
    AdminPalette c,
    String name,
    double? baseline,
    double? latest,
  ) {
    final unit = unitForProductName(name);

    Widget figure(Widget marker, String label, String value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marker,
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12)),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: 20,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          name,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        figure(
          Container(width: 14, height: 3, color: c.green),
          'Latest average',
          latest == null ? '—' : formatPriceWithUnit(latest, unit),
        ),
        figure(
          // Dashed, like the baseline line on the chart.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 2,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                  color: c.textSecondary,
                ),
            ],
          ),
          'Admin baseline',
          baseline == null ? 'Not set' : formatPriceWithUnit(baseline, unit),
        ),
      ],
    );
  }

  LineChartData _chartData(
    AdminPalette c,
    List<double?> weekly,
    double? baseline,
  ) {
    final spots = <FlSpot>[
      for (var i = 0; i < weekly.length; i++)
        if (weekly[i] != null) FlSpot(i.toDouble(), weekly[i]!),
    ];
    final values = [...spots.map((s) => s.y), ?baseline];
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final pad = ((rawMax - rawMin).abs() < 1
        ? rawMax * 0.1 + 1
        : (rawMax - rawMin) * 0.2);
    final minY = (rawMin - pad).clamp(0, double.infinity).toDouble();
    final maxY = rawMax + pad;
    final lastIndex = (weekly.length - 1).toDouble();
    final axisStyle = TextStyle(color: c.textSecondary, fontSize: 11);

    return LineChartData(
      minY: minY,
      maxY: maxY,
      minX: 0,
      maxX: lastIndex < 1 ? 1 : lastIndex,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: ((maxY - minY) / 4).clamp(0.5, double.infinity),
        getDrawingHorizontalLine: (_) =>
            FlLine(color: c.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= weekly.length) return const SizedBox.shrink();
              final weeksAgo = weekly.length - 1 - i;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  weeksAgo == 0 ? 'Now' : '-${weeksAgo}w',
                  style: axisStyle,
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '₱${value.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: axisStyle,
              ),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        // The trend: the dashboard's green.
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: c.green,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: c.green.withValues(alpha: 0.10),
          ),
        ),
        // The baseline: a neutral dashed line, so it reads as a reference
        // rather than as a second series.
        if (baseline != null)
          LineChartBarData(
            spots: [
              FlSpot(0, baseline),
              FlSpot(lastIndex < 1 ? 1 : lastIndex, baseline),
            ],
            isCurved: false,
            color: c.textSecondary,
            barWidth: 1.5,
            dashArray: const [6, 4],
            dotData: const FlDotData(show: false),
          ),
      ],
    );
  }
}

/// The commodity search on the Price Trend card: type to get matching
/// commodities suggested, pick one to load its chart. Shows the current
/// commodity until the admin starts typing.
class AdminCommoditySearchField extends StatelessWidget {
  final List<String> commodities;
  final String? selected;
  final ValueChanged<String> onSelected;

  const AdminCommoditySearchField({
    super.key,
    required this.commodities,
    required this.selected,
    required this.onSelected,
  });

  static const double _width = 240;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return SizedBox(
      width: _width,
      child: Autocomplete<String>(
        initialValue: TextEditingValue(text: selected ?? ''),
        // With the current commodity still in the field, list them all;
        // once the admin types something else, only the matches.
        optionsBuilder: (value) => matchCommodities(
          commodities,
          value.text.trim() == (selected ?? '') ? '' : value.text,
        ),
        onSelected: onSelected,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (_) => onSubmitted(),
            // Select the current name on focus, so typing replaces it.
            onTap: () => controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            ),
            style: TextStyle(color: c.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search commodity',
              hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 18, color: c.textSecondary),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 36,
              ),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminRadii.pill),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminRadii.pill),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminRadii.pill),
                borderSide: BorderSide(color: c.green, width: 1.5),
              ),
            ),
          );
        },
        optionsViewBuilder: (context, onPick, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: c.surface,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: c.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _width,
                    maxHeight: 240,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final name = options.elementAt(i);
                      final isCurrent = name == selected;
                      final highlighted =
                          AutocompleteHighlightedOption.of(context) == i;
                      return InkWell(
                        onTap: () => onPick(name),
                        child: Container(
                          color: highlighted ? c.surfaceAlt : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isCurrent ? c.green : c.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---- Demand by Barangay (ranked bars, red -> orange -> yellow) ----
class AdminDemandByBarangayCard extends StatelessWidget {
  final List<({String barangay, int orderCount, num revenue})> demand;
  final VoidCallback onOpenHeatmap;

  const AdminDemandByBarangayCard({
    super.key,
    required this.demand,
    required this.onOpenHeatmap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final top = demand.take(6).toList();
    final maxCount = top.isEmpty ? 1 : top.first.orderCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Demand by Barangay',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenHeatmap,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: Text(
                  'Open heatmap',
                  style: TextStyle(color: c.green, fontSize: 12),
                ),
              ),
            ],
          ),
          Text(
            'Buyer demand, last 30 days',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (top.isEmpty)
            const AdminEmptyState(
              icon: Icons.location_on_outlined,
              title: 'No buyer location data yet',
              subtitle:
                  'Fills in as buyers set their barangay and place orders.',
            )
          else
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == top.length - 1 ? 0 : 12),
                child: _bar(c, top[i], maxCount, i, top.length),
              ),
        ],
      ),
    );
  }

  Widget _bar(
    AdminPalette c,
    ({String barangay, int orderCount, num revenue}) d,
    int maxCount,
    int index,
    int total,
  ) {
    // 0 = highest demand (red) -> 1 = lowest shown (yellow).
    final t = total <= 1 ? 0.0 : index / (total - 1);
    final color = t <= 0.5
        ? Color.lerp(c.red, c.amber, t * 2)!
        : Color.lerp(c.amber, const Color(0xFFFBC02D), (t - 0.5) * 2)!;
    final width = maxCount <= 0
        ? 0.0
        : (d.orderCount / maxCount).clamp(0.05, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                d.barangay,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${d.orderCount} order(s)',
              style: TextStyle(color: c.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: width,
            minHeight: 8,
            backgroundColor: c.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ---- New Registrations (grouped bar chart) ----
class AdminRegistrationsCard extends StatelessWidget {
  final List<({String label, int farmers, int buyers})> registrations;
  const AdminRegistrationsCard({super.key, required this.registrations});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final hasData = registrations.any((r) => r.farmers > 0 || r.buyers > 0);
    final maxCount = registrations.fold<int>(
      1,
      (m, r) => [m, r.farmers, r.buyers].reduce((a, b) => a > b ? a : b),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Registrations',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _legendDot(c, c.green, 'Farmers'),
              const SizedBox(width: 14),
              _legendDot(c, c.blue, 'Buyers'),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const AdminEmptyState(
              icon: Icons.person_add_alt_outlined,
              title: 'No new registrations yet',
              subtitle: 'Farmer and buyer sign-ups will appear here.',
            )
          else
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxCount * 1.25,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= registrations.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              registrations[i].label,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < registrations.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: registrations[i].farmers.toDouble(),
                            color: c.green,
                            width: 8,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          BarChartRodData(
                            toY: registrations[i].buyers.toDouble(),
                            color: c.blue,
                            width: 8,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendDot(AdminPalette c, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
    ],
  );
}

// ---- Verification Status (donut) ----
class AdminVerificationStatusCard extends StatelessWidget {
  final int approved;
  final int rejected;
  final int pending;
  final VoidCallback onOpenVerification;

  const AdminVerificationStatusCard({
    super.key,
    required this.approved,
    required this.rejected,
    required this.pending,
    required this.onOpenVerification,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final total = approved + rejected + pending;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Verification Status',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenVerification,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: Text(
                  'Review',
                  style: TextStyle(color: c.green, fontSize: 12),
                ),
              ),
            ],
          ),
          Text(
            'Farmer applications',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            const AdminEmptyState(
              icon: Icons.fact_check_outlined,
              title: 'No applications yet',
              subtitle: 'Farmer verification requests will appear here.',
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: PieChart(
                    PieChartData(
                      sections: [
                        if (approved > 0)
                          PieChartSectionData(
                            value: approved.toDouble(),
                            color: c.green,
                            showTitle: false,
                            radius: 16,
                          ),
                        if (pending > 0)
                          PieChartSectionData(
                            value: pending.toDouble(),
                            color: c.amber,
                            showTitle: false,
                            radius: 16,
                          ),
                        if (rejected > 0)
                          PieChartSectionData(
                            value: rejected.toDouble(),
                            color: c.red,
                            showTitle: false,
                            radius: 16,
                          ),
                      ],
                      centerSpaceRadius: 28,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _statRow(c, c.green, 'Approved', approved),
                      const SizedBox(height: 8),
                      _statRow(c, c.amber, 'Pending', pending),
                      const SizedBox(height: 8),
                      _statRow(c, c.red, 'Rejected', rejected),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statRow(AdminPalette c, Color color, String label, int count) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: c.textPrimary, fontSize: 12.5),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ---- Tiny sparkline for a Live Commodity Prices card ----
class AdminPriceSparkline extends StatelessWidget {
  final List<double?> weeklyPrices;
  final Color color;

  const AdminPriceSparkline({
    super.key,
    required this.weeklyPrices,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < weeklyPrices.length; i++)
        if (weeklyPrices[i] != null) FlSpot(i.toDouble(), weeklyPrices[i]!),
    ];
    // Fewer than 2 real points can't draw a trend — an honest gap, not a
    // fabricated flat line.
    if (spots.length < 2) return const SizedBox.shrink();

    final values = spots.map((s) => s.y);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() < 1 ? 1.0 : (maxY - minY) * 0.15;

    return SizedBox(
      height: 28,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 1.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
