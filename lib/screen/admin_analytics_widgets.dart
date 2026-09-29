import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import 'admin_dashboard_screen.dart' show AdminThemeScope, AdminPalette, AdminEmptyState;

// ============================================================
// New chart widgets for the Admin Analytics Dashboard redesign. Every
// widget here takes already-computed, real data (no mock/sample values
// anywhere) — the Firestore reads and aggregation live in
// admin_dashboard_screen.dart, which passes plain typed data down so
// this file stays decoupled from its private helper types.
// ============================================================

// ---- Sales by Category (donut) ----
class AdminSalesByCategoryCard extends StatelessWidget {
  final Map<String, num> categoryRevenue;
  const AdminSalesByCategoryCard({super.key, required this.categoryRevenue});

  static const List<Color> _palette = [
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFF2196F3),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF795548),
  ];

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final entries = categoryRevenue.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<num>(0, (sum, e) => sum + e.value);

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
          Text('Sales by Category',
              style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Share of completed-order revenue', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const AdminEmptyState(
              icon: Icons.pie_chart_outline,
              title: 'No sales yet',
              subtitle: 'Category breakdown will appear once orders complete.',
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: [
                            for (var i = 0; i < entries.length; i++)
                              PieChartSectionData(
                                value: entries[i].value.toDouble(),
                                color: _palette[i % _palette.length],
                                radius: 22,
                                showTitle: false,
                              ),
                          ],
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatPeso(total),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Total', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 8),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration:
                                    BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(entries[i].key,
                                    style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text(
                                total > 0 ? '${(entries[i].value / total * 100).toStringAsFixed(0)}%' : '0%',
                                style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---- Top-Selling Products (ranked horizontal bars, top 5) ----
class AdminTopProductsCard extends StatelessWidget {
  final List<({String name, num revenue, num quantity})> products;
  const AdminTopProductsCard({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final maxRevenue =
        products.isEmpty ? 1.0 : products.map((p) => p.revenue.toDouble()).reduce((a, b) => a > b ? a : b);

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
            children: [
              Icon(Icons.emoji_events_outlined, size: 18, color: c.amber),
              const SizedBox(width: 8),
              Text('Top-Selling Products',
                  style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Platform-wide, by completed-order revenue', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          if (products.isEmpty)
            const AdminEmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No completed sales yet',
              subtitle: 'Top products will appear here once orders complete.',
            )
          else
            for (var i = 0; i < products.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == products.length - 1 ? 0 : 14),
                child: _row(c, i, products[i], maxRevenue),
              ),
        ],
      ),
    );
  }

  Widget _row(AdminPalette c, int index, ({String name, num revenue, num quantity}) p, double maxRevenue) {
    final isTop = index == 0;
    final barValue = maxRevenue <= 0 ? 0.0 : (p.revenue / maxRevenue).clamp(0.03, 1.0);
    return Container(
      padding: EdgeInsets.all(isTop ? 12 : 0),
      decoration: isTop
          ? BoxDecoration(
              color: c.amberBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.amber.withValues(alpha: 0.35)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text('#${index + 1}',
                style: TextStyle(color: isTop ? c.amber : c.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(formatPeso(p.revenue), style: TextStyle(color: c.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: barValue,
                    minHeight: 6,
                    backgroundColor: c.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(isTop ? c.amber : c.green),
                  ),
                ),
                const SizedBox(height: 2),
                Text('${formatStock(p.quantity, unitForProductName(p.name))} sold',
                    style: TextStyle(color: c.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Price Trend vs. Baseline (line chart + commodity chips) ----
class AdminPriceTrendCard extends StatefulWidget {
  final Map<String, double> baselineByCommodity;
  final Map<String, List<double?>> weeklyPricesByCommodity;

  const AdminPriceTrendCard({
    super.key,
    required this.baselineByCommodity,
    required this.weeklyPricesByCommodity,
  });

  @override
  State<AdminPriceTrendCard> createState() => _AdminPriceTrendCardState();
}

class _AdminPriceTrendCardState extends State<AdminPriceTrendCard> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final names = widget.baselineByCommodity.keys.toList()..sort();
    if (_selected == null || !names.contains(_selected)) {
      _selected = names.isNotEmpty ? names.first : null;
    }

    final weekly = _selected == null ? const <double?>[] : (widget.weeklyPricesByCommodity[_selected] ?? const []);
    final baseline = _selected == null ? null : widget.baselineByCommodity[_selected];
    final hasData = weekly.any((v) => v != null);

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
          Text('Price Trend vs. Baseline',
              style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Weekly average price from completed orders, dashed line = admin baseline',
              style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 14),
          if (names.isEmpty)
            const AdminEmptyState(
              icon: Icons.show_chart,
              title: 'No commodities tracked yet',
              subtitle: 'Set a baseline price in Manage Prices first.',
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in names)
                  ChoiceChip(
                    label: Text(name),
                    selected: _selected == name,
                    onSelected: (_) => setState(() => _selected = name),
                    selectedColor: c.green,
                    backgroundColor: c.surfaceAlt,
                    side: BorderSide(color: c.border),
                    labelStyle: TextStyle(
                      color: _selected == name ? Colors.white : c.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!hasData)
              AdminEmptyState(
                icon: Icons.show_chart,
                title: 'No completed sales for ${_selected ?? "this commodity"} yet',
                subtitle: 'The trend line fills in once matching orders complete.',
              )
            else
              SizedBox(height: 190, child: LineChart(_chartData(c, weekly, baseline))),
          ],
        ],
      ),
    );
  }

  LineChartData _chartData(AdminPalette c, List<double?> weekly, double? baseline) {
    final spots = <FlSpot>[
      for (var i = 0; i < weekly.length; i++)
        if (weekly[i] != null) FlSpot(i.toDouble(), weekly[i]!),
    ];
    final values = [...spots.map((s) => s.y), ?baseline];
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final pad = ((rawMax - rawMin).abs() < 1 ? rawMax * 0.1 + 1 : (rawMax - rawMin) * 0.2);
    final minY = (rawMin - pad).clamp(0, double.infinity).toDouble();
    final maxY = rawMax + pad;
    final lastIndex = (weekly.length - 1).toDouble();

    return LineChartData(
      minY: minY,
      maxY: maxY,
      minX: 0,
      maxX: lastIndex < 1 ? 1 : lastIndex,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: ((maxY - minY) / 4).clamp(0.5, double.infinity),
        getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                child: Text(weeksAgo == 0 ? 'Now' : '-${weeksAgo}w',
                    style: TextStyle(color: c.textSecondary, fontSize: 10)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (value, meta) =>
                Text('₱${value.toStringAsFixed(0)}', style: TextStyle(color: c.textSecondary, fontSize: 10)),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: c.green,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: c.green.withValues(alpha: 0.12)),
        ),
        if (baseline != null)
          LineChartBarData(
            spots: [FlSpot(0, baseline), FlSpot(lastIndex < 1 ? 1 : lastIndex, baseline)],
            isCurved: false,
            color: c.amber,
            barWidth: 2,
            dashArray: const [6, 4],
            dotData: const FlDotData(show: false),
          ),
      ],
    );
  }
}

// ---- Demand by Barangay (ranked bars, red -> orange -> yellow) ----
class AdminDemandByBarangayCard extends StatelessWidget {
  final List<({String barangay, int orderCount, num revenue})> demand;
  final VoidCallback onOpenHeatmap;

  const AdminDemandByBarangayCard({super.key, required this.demand, required this.onOpenHeatmap});

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
                child: Text('Demand by Barangay',
                    style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: onOpenHeatmap,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: Text('Open heatmap', style: TextStyle(color: c.green, fontSize: 12)),
              ),
            ],
          ),
          Text('Buyer demand, last 30 days', style: TextStyle(color: c.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          if (top.isEmpty)
            const AdminEmptyState(
              icon: Icons.location_on_outlined,
              title: 'No buyer location data yet',
              subtitle: 'Fills in as buyers set their barangay and place orders.',
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

  Widget _bar(AdminPalette c, ({String barangay, int orderCount, num revenue}) d, int maxCount, int index, int total) {
    // 0 = highest demand (red) -> 1 = lowest shown (yellow).
    final t = total <= 1 ? 0.0 : index / (total - 1);
    final color = t <= 0.5 ? Color.lerp(c.red, c.amber, t * 2)! : Color.lerp(c.amber, const Color(0xFFFBC02D), (t - 0.5) * 2)!;
    final width = maxCount <= 0 ? 0.0 : (d.orderCount / maxCount).clamp(0.05, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(d.barangay,
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${d.orderCount} order(s)', style: TextStyle(color: c.textSecondary, fontSize: 11)),
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
          Text('New Registrations', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= registrations.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(registrations[i].label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
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
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
                child: Text('Verification Status',
                    style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: onOpenVerification,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: Text('Review', style: TextStyle(color: c.green, fontSize: 12)),
              ),
            ],
          ),
          Text('Farmer applications', style: TextStyle(color: c.textSecondary, fontSize: 12)),
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
                          PieChartSectionData(value: approved.toDouble(), color: c.green, showTitle: false, radius: 16),
                        if (pending > 0)
                          PieChartSectionData(value: pending.toDouble(), color: c.amber, showTitle: false, radius: 16),
                        if (rejected > 0)
                          PieChartSectionData(value: rejected.toDouble(), color: c.red, showTitle: false, radius: 16),
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(color: c.textPrimary, fontSize: 12.5))),
        Text('$count', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

// ---- Tiny sparkline for a Live Commodity Prices card ----
class AdminPriceSparkline extends StatelessWidget {
  final List<double?> weeklyPrices;
  final Color color;

  const AdminPriceSparkline({super.key, required this.weeklyPrices, required this.color});

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
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
            ),
          ],
        ),
      ),
    );
  }
}
