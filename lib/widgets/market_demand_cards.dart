import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';
import 'market_card_shell.dart';
import 'retry_message.dart';
import '../l10n/tr.dart';

/// The Farmer Dashboard's marketplace-wide analytics: Best-Selling Products
/// and, below it, Top Buyer Locations — both for [month], the same month
/// the Sales Performance card is showing. See [MarketDemandService] for
/// what is counted and how demand level and trend are decided.
class MarketDemandCards extends StatefulWidget {
  final DateTime month;

  /// On the two cards, for the Market tab's first-time hints.
  final Key? bestSellersKey;
  final Key? locationsKey;

  const MarketDemandCards({
    super.key,
    required this.month,
    this.bestSellersKey,
    this.locationsKey,
  });

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
                KeyedSubtree(
                  key: widget.bestSellersKey,
                  child: _card(
                    title: tr(context).bestSellingProducts,
                    subtitle: tr(
                      context,
                    ).bestSellersSubtitle(MarketDemandService.bestSellerLimit),
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
                    onToggle: () =>
                        setState(() => _allProducts = !_allProducts),
                  ),
                ),
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: widget.locationsKey,
                  child: _card(
                    title: tr(context).topBuyerLocations,
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
                ) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey[200]),
                  rows[i],
                ],
                if (rows.length > _collapsed)
                  MarketCardToggle(expanded: expanded, onPressed: onToggle),
              ],
            ),
    );
  }

  // One ranked entry: a single plain line (no panel), so a long list
  // stays easy to scan.
  Widget _line(int rank, String name, List<Widget> trailing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        _rank(rank),
        const SizedBox(width: 8),
        Expanded(child: _name(name)),
        for (final widget in trailing) ...[const SizedBox(width: 8), widget],
      ],
    ),
  );

  // The rank as a plain number; the leader in the brand's dark green.
  Widget _rank(int rank) => SizedBox(
    width: 22,
    child: Text(
      '$rank',
      style: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: rank == 1 ? AppTheme.dark : Colors.grey[500],
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

  // Short, so the line fits: High / Moderate / Low.
  Widget _demandTag(DemandLevel level) {
    final (String label, Color color) = switch (level) {
      DemandLevel.high => ('High', AppTheme.mid),
      DemandLevel.moderate => ('Moderate', Colors.orange.shade800),
      DemandLevel.low => ('Low', Colors.grey.shade700),
    };
    return _pill(label, color);
  }

  Widget _name(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.montserrat(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  );

  // Rank, product, its trend arrow and demand — on one line.
  Widget _bestSellerRow(int rank, BestSeller item) {
    final (String trend, IconData icon, Color color) = switch (item.trend) {
      DemandTrend.rising => ('Rising', Icons.trending_up_rounded, AppTheme.mid),
      DemandTrend.stable => (
        'Stable',
        Icons.trending_flat_rounded,
        Colors.grey.shade600,
      ),
      DemandTrend.declining => (
        'Declining',
        Icons.trending_down_rounded,
        Colors.red.shade700,
      ),
    };
    return _line(rank, item.commodity, [
      Tooltip(
        message: trend,
        child: Icon(icon, size: 18, color: color),
      ),
      _demandTag(item.demand),
    ]);
  }

  // Rank, area, demand and its share against the busiest area — on one
  // line.
  Widget _locationRow(int rank, BuyerLocation location) {
    final share = (location.relativeDemand.clamp(0.0, 1.0) * 100).round();
    return _line(rank, location.area, [
      _demandTag(location.demand),
      SizedBox(
        width: 38,
        child: Text(
          '$share%',
          textAlign: TextAlign.right,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.dark,
          ),
        ),
      ),
    ]);
  }
}
