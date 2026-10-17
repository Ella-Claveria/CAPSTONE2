import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/market_price_helpers.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart'
    show AdminThemeScope, AdminPalette, AdminRadii;

// ============================================================
// The Demand Heatmap's colour scale, its legend, and the two panels beside
// the map: Highest Demand Areas and Most Purchased Products by Area.
// Everything here shows what it is given — completed buyer purchases,
// counted per buyer area — and nothing else.
// ============================================================

/// Heat colours, low demand to high.
const Color kHeatLow = Color(0xFF43A047); // green
const Color kHeatMedium = Color(0xFFFFC107); // yellow
const Color kHeatMediumHigh = Color(0xFFFF9800); // orange
const Color kHeatHigh = Color(0xFFE53935); // red

/// The scale never tops out below this many purchases: with very little
/// data, an area with one or two purchases is low demand (green), not
/// "the highest" (red) merely because nothing else has more.
const int kHeatScaleFloor = 5;

/// How strong an area's demand is, 0–1: its completed purchases against
/// the busiest area's (or [kHeatScaleFloor], whichever is more).
double demandIntensity(num purchases, num busiest) =>
    (purchases / math.max(busiest, kHeatScaleFloor)).clamp(0.0, 1.0).toDouble();

/// Green → yellow → orange → red.
Color heatColorForIntensity(double t) {
  final x = t.clamp(0.0, 1.0);
  if (x <= 1 / 3) return Color.lerp(kHeatLow, kHeatMedium, x * 3)!;
  if (x <= 2 / 3) {
    return Color.lerp(kHeatMedium, kHeatMediumHigh, (x - 1 / 3) * 3)!;
  }
  return Color.lerp(kHeatMediumHigh, kHeatHigh, (x - 2 / 3) * 3)!;
}

String heatLevelLabel(double t) => t > 2 / 3
    ? 'High Demand'
    : t > 1 / 3
    ? 'Medium Demand'
    : 'Low Demand';

/// The map's legend: the colour scale with what each end means.
class AdminHeatLegend extends StatelessWidget {
  /// What the colours count.
  final String title;

  const AdminHeatLegend({super.key, this.title = 'Completed purchases'});

  @override
  Widget build(BuildContext context) {
    // Every row has the same swatch — one pill of the same size, in one
    // colour or (for medium) blending its two — so the labels line up.
    Widget entry(List<Color> colors, String label) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: colors.length == 1 ? colors.single : null,
              gradient: colors.length == 1
                  ? null
                  : LinearGradient(colors: colors),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      // As wide as its longest label, with the colour bar spanning all of
      // it rather than stopping short.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [kHeatLow, kHeatMedium, kHeatMediumHigh, kHeatHigh],
                ),
              ),
            ),
            const SizedBox(height: 3),
            entry(const [kHeatLow], 'Green = Low Demand'),
            entry(const [
              kHeatMedium,
              kHeatMediumHigh,
            ], 'Yellow/Orange = Medium Demand'),
            entry(const [kHeatHigh], 'Red = High Demand'),
          ],
        ),
      ),
    );
  }
}

/// The shell both side panels share, so they match.
class _DemandPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  /// True under a row of tabs: the top-left corner is square, where the
  /// first tab joins the panel.
  final bool tabbed;

  const _DemandPanel({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    this.tabbed = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: tabbed
            ? const BorderRadius.only(
                topRight: Radius.circular(AdminRadii.card),
                bottomLeft: Radius.circular(AdminRadii.card),
                bottomRight: Radius.circular(AdminRadii.card),
              )
            : BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          // One line whether or not there is a subtitle, so the two
          // panels' lists start level.
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 8),
            child: Text(
              subtitle ?? ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

Widget _panelEmpty(AdminPalette c, String text) => Center(
  child: Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: c.textMuted, fontSize: 12.5),
    ),
  ),
);

Widget _rankBadge(AdminPalette c, int rank, {required bool strong}) =>
    Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? c.green : c.greenBg,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: strong ? (c.isDark ? AppTheme.dark : Colors.white) : c.green,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

/// HIGHEST DEMAND AREAS — buyer areas ranked by completed purchases, each
/// with its rank, name and count, and a dot in its colour on the map.
/// Clicking one selects it (see [AdminAreaProductsPanel]).
class AdminDemandAreasPanel extends StatelessWidget {
  /// Ranked, most completed purchases first.
  final List<({String area, int orderCount})> areas;
  final String? selectedArea;
  final ValueChanged<String> onSelect;
  final String emptyText;

  /// What is being counted — purchases by default; the search layer passes
  /// its own wording.
  final String title;
  final String subtitle;
  final String unit;
  final String unitPlural;

  /// True when the panel sits under the Purchases / Searches tabs.
  final bool tabbed;

  const AdminDemandAreasPanel({
    super.key,
    required this.areas,
    required this.selectedArea,
    required this.onSelect,
    required this.emptyText,
    this.title = 'Highest Demand Areas',
    this.subtitle = 'By completed buyer purchases · select an area',
    this.unit = 'purchase',
    this.unitPlural = 'purchases',
    this.tabbed = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final busiest = areas.isEmpty ? 0 : areas.first.orderCount;
    return _DemandPanel(
      icon: Icons.local_fire_department_outlined,
      title: title,
      subtitle: areas.isEmpty ? null : subtitle,
      tabbed: tabbed,
      child: areas.isEmpty
          ? _panelEmpty(c, emptyText)
          : ListView.builder(
              itemCount: areas.length,
              itemBuilder: (context, i) {
                final area = areas[i];
                final selected = area.area == selectedArea;
                final intensity = demandIntensity(area.orderCount, busiest);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: selected ? c.greenBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelect(area.area),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            _rankBadge(c, i + 1, strong: selected),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                area.area,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: heatLevelLabel(intensity),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: heatColorForIntensity(intensity),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${area.orderCount} '
                              '${area.orderCount == 1 ? unit : unitPlural}',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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

/// MOST PURCHASED PRODUCTS BY AREA — what buyers in the selected area
/// bought in completed orders, ranked by total quantity: the product, its
/// category, the quantity and the number of completed orders.
class AdminAreaProductsPanel extends StatelessWidget {
  /// The selected area; null when the period has no demand at all.
  final String? area;
  final List<
    ({
      String product,
      String category,
      double quantity,
      String unit,
      int orders,
    })
  >
  products;
  final String emptyText;

  const AdminAreaProductsPanel({
    super.key,
    required this.area,
    required this.products,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return _DemandPanel(
      icon: Icons.shopping_basket_outlined,
      title: 'Most Purchased Products by Area',
      subtitle: area,
      child: area == null || products.isEmpty
          ? _panelEmpty(c, emptyText)
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      _rankBadge(c, i + 1, strong: i == 0),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.product,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              p.category.isEmpty ? 'Uncategorized' : p.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${p.orders} ${p.orders == 1 ? 'order' : 'orders'} / '
                        '${formatStock(p.quantity, p.unit)}',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// MOST SEARCHED BY AREA — what buyers in the selected area searched for,
/// most searched first. The search layer's counterpart to
/// [AdminAreaProductsPanel]: searches show interest, not purchases.
class AdminAreaSearchesPanel extends StatelessWidget {
  /// The selected area; null when the period has no placed searches.
  final String? area;
  final List<({String term, int searches})> terms;
  final String emptyText;

  const AdminAreaSearchesPanel({
    super.key,
    required this.area,
    required this.terms,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return _DemandPanel(
      icon: Icons.search,
      title: 'Most Searched by Area',
      subtitle: area,
      child: area == null || terms.isEmpty
          ? _panelEmpty(c, emptyText)
          : ListView.builder(
              itemCount: terms.length,
              itemBuilder: (context, i) {
                final t = terms[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      _rankBadge(c, i + 1, strong: i == 0),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.term,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${t.searches} '
                        '${t.searches == 1 ? 'search' : 'searches'}',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
