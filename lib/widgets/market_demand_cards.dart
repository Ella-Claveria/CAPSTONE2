import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';
import 'market_card_shell.dart';
import 'retry_message.dart';

/// The Farmer Dashboard's marketplace-wide analytics: Best-Selling Products
/// and, below it, Top Buyer Locations — both for [month], the same month
/// the Sales Performance card is showing. See [MarketDemandService] for
/// what is counted and how demand level and trend are decided.
class MarketDemandCards extends StatefulWidget {
  final DateTime month;

  const MarketDemandCards({super.key, required this.month});

  @override
  State<MarketDemandCards> createState() => _MarketDemandCardsState();
}

class _MarketDemandCardsState extends State<MarketDemandCards> {
  // Created once — not on every dashboard rebuild.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sales = _salesStream();

  Stream<QuerySnapshot<Map<String, dynamic>>> _salesStream() =>
      FirebaseFirestore.instance.collection('market_sales').snapshots();

  // Rows each list shows on the dashboard before "View All".
  static const int _collapsed = 5;
  bool _allProducts = false;
  bool _allLocations = false;

  static TextStyle _muted([double size = 11.5]) =>
      GoogleFonts.montserrat(fontSize: size, color: Colors.grey[600]);

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM y').format(widget.month);
    final tagLabel = DateFormat('MMM y').format(widget.month);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return RetryMessage(
            message:
                'Could not load marketplace sales. Check your connection and retry.',
            onRetry: () => setState(() => _sales = _salesStream()),
          );
        }
        final loading = !snapshot.hasData;
        final sales =
            snapshot.data?.docs.map((doc) => doc.data()).toList() ??
            const <Map<String, dynamic>>[];

        // Also rebuilt when the Admin changes the commodity list, since
        // names, categories and units come from it.
        return ListenableBuilder(
          listenable: CommodityRegistry.instance,
          builder: (context, _) {
            final bestSellers = MarketDemandService.bestSellers(
              sales: sales,
              month: widget.month,
            );
            final locations = MarketDemandService.topBuyerLocations(
              sales: sales,
              month: widget.month,
            );
            return Column(
              children: [
                _card(
                  title: 'Best-Selling Products',
                  subtitle:
                      'Top ${MarketDemandService.bestSellerLimit} most purchased products across AgriTrade+',
                  tag: tagLabel,
                  loading: loading,
                  emptyIcon: Icons.shopping_basket_outlined,
                  emptyText:
                      'No completed orders in $monthLabel yet. Popular '
                      'products will appear here as buyers complete orders.',
                  rows: [
                    for (var i = 0; i < bestSellers.length; i++)
                      _bestSellerRow(i + 1, bestSellers[i]),
                  ],
                  expanded: _allProducts,
                  onToggle: () => setState(() => _allProducts = !_allProducts),
                ),
                const SizedBox(height: 16),
                _card(
                  title: 'Top Buyer Locations',
                  tag: tagLabel,
                  loading: loading,
                  emptyIcon: Icons.map_outlined,
                  emptyText:
                      'No buyer locations on record for completed orders in '
                      '$monthLabel yet.',
                  rows: [
                    for (var i = 0; i < locations.length; i++)
                      _locationRow(i + 1, locations[i]),
                  ],
                  expanded: _allLocations,
                  onToggle: () =>
                      setState(() => _allLocations = !_allLocations),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    required String tag,
    required bool loading,
    required IconData emptyIcon,
    required String emptyText,
    required List<Widget> rows,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return MarketCardShell(
      title: title,
      subtitle: subtitle,
      tag: tag,
      child: loading
          ? const MarketCardLoading()
          : rows.isEmpty
          ? MarketCardEmpty(icon: emptyIcon, message: emptyText)
          : Column(
              children: [
                // The dashboard shows the first few; the rest open in place.
                for (
                  var i = 0;
                  i <
                      (expanded
                          ? rows.length
                          : rows.length.clamp(0, _collapsed));
                  i++
                ) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
                if (rows.length > _collapsed)
                  MarketCardToggle(expanded: expanded, onPressed: onToggle),
              ],
            ),
    );
  }

  // One ranked entry on its own soft panel; the leader a shade stronger.
  Widget _rowPanel(int rank, Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
    decoration: BoxDecoration(
      color: rank == 1
          ? AppTheme.accent.withValues(alpha: 0.38)
          : const Color(0xFFF7FAF5),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );

  Widget _rank(int rank) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: rank == 1 ? AppTheme.dark : Colors.white,
      shape: BoxShape.circle,
      border: rank == 1 ? null : Border.all(color: const Color(0xFFDCE8D3)),
    ),
    child: Text(
      '$rank',
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: rank == 1 ? Colors.white : AppTheme.dark,
      ),
    ),
  );

  Widget _pill(String label, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _demandTag(DemandLevel level) {
    final (String label, Color color) = switch (level) {
      DemandLevel.high => ('High Demand', AppTheme.mid),
      DemandLevel.moderate => ('Moderate Demand', Colors.orange.shade800),
      DemandLevel.low => ('Low Demand', Colors.grey.shade700),
    };
    return _pill(label, color);
  }

  Widget _name(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.montserrat(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    ),
  );

  Widget _bestSellerRow(int rank, BestSeller item) {
    final (
      String trendLabel,
      IconData trendIcon,
      Color trendColor,
    ) = switch (item.trend) {
      DemandTrend.rising => ('Rising', Icons.trending_up_rounded, AppTheme.mid),
      DemandTrend.stable => (
        'Stable',
        Icons.trending_flat_rounded,
        Colors.grey.shade700,
      ),
      DemandTrend.declining => (
        'Declining',
        Icons.trending_down_rounded,
        Colors.red.shade700,
      ),
    };
    final details = [
      if (item.category.isNotEmpty) item.category,
      if (item.mostlyWholesale != null)
        item.mostlyWholesale! ? 'Mostly Wholesale' : 'Mostly Retail',
      'per ${item.unit}',
    ].join(' · ');

    return _rowPanel(
      rank,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rank(rank),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _name(item.commodity),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _muted(),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _demandTag(item.demand),
                    _pill(trendLabel, trendColor, icon: trendIcon),
                  ],
                ),
                if (item.topBuyerArea.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          'Top buyer area: ${item.topBuyerArea}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _muted(),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationRow(int rank, BuyerLocation location) {
    final share = (location.relativeDemand.clamp(0.0, 1.0) * 100).round();
    return _rowPanel(
      rank,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rank(rank),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _name(location.area)),
                    const SizedBox(width: 8),
                    _demandTag(location.demand),
                  ],
                ),
                const SizedBox(height: 8),
                // Relative demand: this area against the busiest one.
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: location.relativeDemand,
                          minHeight: 7,
                          color: rank == 1 ? AppTheme.dark : AppTheme.mid,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '$share%',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Most purchased: ${location.mostPurchased}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _muted(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
