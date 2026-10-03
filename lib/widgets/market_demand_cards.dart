import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';
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
                  icon: Icons.emoji_events_outlined,
                  title: 'Best-Selling Products',
                  subtitle:
                      'Top ${MarketDemandService.bestSellerLimit} most purchased products across AgriTrade+ · $monthLabel',
                  loading: loading,
                  emptyText:
                      'No completed orders across AgriTrade+ in $monthLabel yet. '
                      'Popular products will appear here as buyers complete orders.',
                  rows: [
                    for (var i = 0; i < bestSellers.length; i++)
                      _bestSellerRow(i + 1, bestSellers[i]),
                  ],
                  expanded: _allProducts,
                  onToggle: () => setState(() => _allProducts = !_allProducts),
                ),
                const SizedBox(height: 16),
                _card(
                  icon: Icons.place_outlined,
                  title: 'Top Buyer Locations',
                  subtitle:
                      'Where completed orders came from across AgriTrade+ · $monthLabel',
                  loading: loading,
                  emptyText:
                      'No buyer locations on record for completed orders in $monthLabel yet.',
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
    required IconData icon,
    required String title,
    required String subtitle,
    required bool loading,
    required String emptyText,
    required List<Widget> rows,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.dark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: _muted(12)),
          const SizedBox(height: 14),
          if (loading)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 2.5,
                color: AppTheme.dark.withValues(alpha: 0.55),
                backgroundColor: AppTheme.dark.withValues(alpha: 0.08),
              ),
            )
          else if (rows.isEmpty)
            Text(
              emptyText,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                color: Colors.grey[500],
                height: 1.4,
              ),
            )
          else ...[
            // The dashboard shows the first few; the rest open in place.
            for (
              var i = 0;
              i < (expanded ? rows.length : rows.length.clamp(0, _collapsed));
              i++
            ) ...[
              if (i > 0) Divider(height: 18, color: Colors.grey.shade200),
              rows[i],
            ],
            if (rows.length > _collapsed)
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: onToggle,
                  iconAlignment: IconAlignment.end,
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                  ),
                  label: Text(expanded ? 'Show Less' : 'View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.dark,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: GoogleFonts.montserrat(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _rank(int rank) => Container(
    width: 30,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.accent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '#$rank',
      style: GoogleFonts.montserrat(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppTheme.dark,
      ),
    ),
  );

  Widget _demandTag(DemandLevel level) {
    final (String label, Color color) = switch (level) {
      DemandLevel.high => ('High Demand', AppTheme.dark),
      DemandLevel.moderate => ('Moderate Demand', Colors.orange.shade800),
      DemandLevel.low => ('Low Demand', Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _name(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GoogleFonts.montserrat(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  );

  Widget _bestSellerRow(int rank, BestSeller item) {
    final (
      String trendLabel,
      IconData trendIcon,
      Color trendColor,
    ) = switch (item.trend) {
      DemandTrend.rising => (
        'Rising',
        Icons.trending_up_rounded,
        AppTheme.dark,
      ),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rank(rank),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _name(item.commodity)),
                  const SizedBox(width: 8),
                  _demandTag(item.demand),
                ],
              ),
              const SizedBox(height: 2),
              Text(details, style: _muted()),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.topBuyerArea.isEmpty
                          ? 'Top buyer area: not on record yet'
                          : 'Top buyer area: ${item.topBuyerArea}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _muted(),
                    ),
                  ),
                  Icon(trendIcon, size: 15, color: trendColor),
                  const SizedBox(width: 3),
                  Text(
                    trendLabel,
                    style: GoogleFonts.montserrat(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: trendColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _locationRow(int rank, BuyerLocation location) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rank(rank),
        const SizedBox(width: 12),
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
              const SizedBox(height: 6),
              // Relative demand: this area against the busiest one.
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: location.relativeDemand,
                  minHeight: 6,
                  color: AppTheme.dark,
                  backgroundColor: const Color(0xFFEFF6E8),
                ),
              ),
              const SizedBox(height: 5),
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
    );
  }
}
