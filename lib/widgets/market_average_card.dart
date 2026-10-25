import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/commodity_master_list.dart';
import '../services/market_price_helpers.dart';
import '../theme/app_theme.dart';
import 'market_card_shell.dart';
import '../l10n/tr.dart';

/// One supported commodity's Current Market Average.
typedef MarketAverageRow = ({String commodity, String unit, double average});

/// The Current Market Average of every supported commodity that has an
/// active listing — the average retail asking price of listings buyers can
/// order from now (see [computeLiveAverage], the same figure the Admin's
/// Price Management shows). A commodity nobody is selling is left out; it
/// is never given the reference price or a zero.
List<MarketAverageRow> currentMarketAverages(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
) => [
  for (final commodity in CommodityRegistry.instance.all)
    if (computeLiveAverage(products, commodity.name) case final average?)
      (commodity: commodity.name, unit: commodity.unit, average: average),
]..sort((a, b) => a.commodity.compareTo(b.commodity));

/// The Farmer Dashboard's Current Market Average card.
class MarketAverageCard extends StatefulWidget {
  /// Every commodity, on the card's own full-list screen; else the first
  /// few and "View all".
  final bool showAll;

  const MarketAverageCard({super.key, this.showAll = false});

  @override
  State<MarketAverageCard> createState() => _MarketAverageCardState();
}

class _MarketAverageCardState extends State<MarketAverageCard> {
  // Created once — not on every dashboard rebuild.
  final Stream<QuerySnapshot<Map<String, dynamic>>> _products =
      FirebaseFirestore.instance.collection('products').snapshots();

  @override
  Widget build(BuildContext context) {
    return MarketCardShell(
      title: tr(context).currentMarketAverage,
      subtitle: tr(context).marketAverageSubtitle,
      tag: tr(context).live,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _products,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const MarketCardEmpty(
              icon: Icons.cloud_off_outlined,
              message:
                  'Could not load marketplace listings. Check your '
                  'connection and try again.',
            );
          }
          if (!snapshot.hasData) return const MarketCardLoading();
          // Rebuilt when the supported commodity list changes too.
          return ListenableBuilder(
            listenable: CommodityRegistry.instance,
            builder: (context, _) =>
                _tiles(currentMarketAverages(snapshot.data!.docs)),
          );
        },
      ),
    );
  }

  Widget _tiles(List<MarketAverageRow> rows) {
    if (rows.isEmpty) {
      return const MarketCardEmpty(
        icon: Icons.storefront_outlined,
        message:
            'No active listings of supported products yet. Prices appear '
            'here as farmers post products.',
      );
    }
    return marketCardRows(
      rows: [for (final row in rows) _tile(row)],
      showAll: widget.showAll,
      openAll: () => openMarketCardScreen(
        context,
        title: tr(context).currentMarketAverage,
        child: const MarketAverageCard(showAll: true),
      ),
    );
  }

  // One commodity on one line: its name, then the price and unit.
  Widget _tile(MarketAverageRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.commodity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatPeso(row.average),
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dark,
                  ),
                ),
                TextSpan(
                  text: ' /${row.unit}',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
