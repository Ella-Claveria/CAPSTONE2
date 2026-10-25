import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/market_demand_index.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';

/// How a demand level reads and its colour — the same on the Farmer's
/// Best-Selling Products card and on the Buyer's product cards.
(String label, Color color) demandLevelStyle(DemandLevel level) =>
    switch (level) {
      DemandLevel.high => ('High', AppTheme.mid),
      DemandLevel.moderate => ('Moderate', Colors.orange.shade800),
      DemandLevel.low => ('Low', Colors.grey.shade700),
    };

/// A demand trend's name, arrow and colour, shared the same way.
(String label, IconData icon, Color color) demandTrendStyle(
  DemandTrend trend,
) => switch (trend) {
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

/// On a product's image in the Buyer's grids: the trend arrow and "High
/// demand" / "Moderate demand" while the product's commodity is on this
/// month's Best-Selling Products list (see [MarketDemandIndex]) — what the
/// farmers see on their Market tab. Nothing for Low demand, or a product
/// not on the list.
class DemandBadge extends StatelessWidget {
  final String productName;

  const DemandBadge({super.key, required this.productName});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MarketDemandIndex.instance,
      builder: (context, _) {
        final best = MarketDemandIndex.instance.forProduct(productName);
        if (best == null || best.demand == DemandLevel.low) {
          return const SizedBox.shrink();
        }
        final (level, levelColor) = demandLevelStyle(best.demand);
        final (trend, icon, trendColor) = demandTrendStyle(best.trend);
        return Semantics(
          label: '$level demand, $trend',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: trendColor),
                const SizedBox(width: 3),
                Text(
                  '$level demand',
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: levelColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
