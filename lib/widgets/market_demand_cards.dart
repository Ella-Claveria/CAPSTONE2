import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';
import 'demand_badge.dart';
import 'market_card_shell.dart';
import 'retry_message.dart';
import '../l10n/tr.dart';

/// The Farmer Dashboard's marketplace-wide analytics: Best-Selling Products
/// and, below it, Top Buyer Locations — both for [month], the same month
/// the Sales Performance card is showing. See [MarketDemandService] for
/// what is counted and how demand level and trend are decided.
///
/// On the dashboard each card lists its first few rows and "View all";
/// that opens a screen with just that card ([only]) listing every row
/// ([showAll]).
class MarketDemandCards extends StatefulWidget {
  final DateTime month;

  /// On the two cards, for the Market tab's first-time hints.
  final Key? bestSellersKey;
  final Key? locationsKey;

  /// Just one of the two cards; both when null.
  final MarketDemandList? only;

  /// Every row, on a card's own full-list screen.
  final bool showAll;

  const MarketDemandCards({
    super.key,
    required this.month,
    this.bestSellersKey,
    this.locationsKey,
    this.only,
    this.showAll = false,
  });

  @override
  State<MarketDemandCards> createState() => _MarketDemandCardsState();
}

enum MarketDemandList { bestSellers, locations }

class _MarketDemandCardsState extends State<MarketDemandCards> {
  // Created once — not on every dashboard rebuild.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sales = _salesStream();

  Stream<QuerySnapshot<Map<String, dynamic>>> _salesStream() =>
      FirebaseFirestore.instance.collection('market_sales').snapshots();

  bool _shows(MarketDemandList list) =>
      widget.only == null || widget.only == list;

  void _openAll(MarketDemandList list, String title) => openMarketCardScreen(
    context,
    title: title,
    child: MarketDemandCards(month: widget.month, only: list, showAll: true),
  );

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
            final bestSellersTitle = tr(context).bestSellingProducts;
            final locationsTitle = tr(context).topBuyerLocations;
            return Column(
              children: [
                if (_shows(MarketDemandList.bestSellers))
                  KeyedSubtree(
                    key: widget.bestSellersKey,
                    child: _card(
                      title: bestSellersTitle,
                      subtitle: tr(context).bestSellersSubtitle(
                        MarketDemandService.bestSellerLimit,
                      ),
                      tag: tagLabel,
                      loading: loading,
                      emptyIcon: Icons.shopping_basket_outlined,
                      emptyText:
                          'No completed orders in $monthLabel yet. Popular '
                          'products will appear here as buyers complete '
                          'orders.',
                      rows: [
                        for (var i = 0; i < bestSellers.length; i++)
                          _bestSellerRow(i + 1, bestSellers[i]),
                      ],
                      openAll: () => _openAll(
                        MarketDemandList.bestSellers,
                        bestSellersTitle,
                      ),
                    ),
                  ),
                if (widget.only == null) const SizedBox(height: 16),
                if (_shows(MarketDemandList.locations))
                  KeyedSubtree(
                    key: widget.locationsKey,
                    child: _card(
                      title: locationsTitle,
                      tag: tagLabel,
                      loading: loading,
                      emptyIcon: Icons.map_outlined,
                      emptyText:
                          'No buyer locations on record for completed orders '
                          'in $monthLabel yet.',
                      rows: [
                        for (var i = 0; i < locations.length; i++)
                          _locationRow(i + 1, locations[i]),
                      ],
                      openAll: () =>
                          _openAll(MarketDemandList.locations, locationsTitle),
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
    required VoidCallback openAll,
  }) {
    return MarketCardShell(
      title: title,
      subtitle: subtitle,
      tag: tag,
      child: loading
          ? const MarketCardLoading()
          : rows.isEmpty
          ? MarketCardEmpty(icon: emptyIcon, message: emptyText)
          : marketCardRows(
              rows: rows,
              showAll: widget.showAll,
              openAll: openAll,
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

  // Short, so the line fits: High / Moderate / Low. The same words and
  // colours as the Buyer's product cards (see DemandBadge).
  Widget _demandTag(DemandLevel level) {
    final (label, color) = demandLevelStyle(level);
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
    final (trend, icon, color) = demandTrendStyle(item.trend);
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
