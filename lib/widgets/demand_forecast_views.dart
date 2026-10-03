import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/demand_forecast_service.dart';
import '../services/market_demand_service.dart';
import '../theme/app_theme.dart';

// The Farmer-facing Demand Forecast: a short card on the dashboard (next
// month, top five) and a full screen behind "View Demand Forecast" where
// the month can be changed. Kept apart from Best-Selling Products and Top
// Buyer Locations, which describe what already happened — this is what is
// expected. See DemandForecastService for how it is estimated.

const String kInsufficientForecastText =
    'Insufficient data for reliable demand forecasting.';

String demandLevelLabel(DemandLevel level) => switch (level) {
  DemandLevel.high => 'High Demand',
  DemandLevel.moderate => 'Moderate Demand',
  DemandLevel.low => 'Low Demand',
};

String demandTrendLabel(DemandTrend trend) => switch (trend) {
  DemandTrend.rising => 'Rising',
  DemandTrend.stable => 'Stable',
  DemandTrend.declining => 'Declining',
};

String forecastConfidenceLabel(ForecastConfidence confidence) =>
    switch (confidence) {
      ForecastConfidence.high => 'High',
      ForecastConfidence.moderate => 'Moderate',
      ForecastConfidence.limited => 'Limited data',
    };

Color _levelColor(DemandLevel level) => switch (level) {
  DemandLevel.high => AppTheme.dark,
  DemandLevel.moderate => Colors.orange.shade800,
  DemandLevel.low => Colors.grey.shade700,
};

(IconData, Color) _trendStyle(DemandTrend trend) => switch (trend) {
  DemandTrend.rising => (Icons.trending_up_rounded, AppTheme.dark),
  DemandTrend.stable => (Icons.trending_flat_rounded, Colors.grey.shade700),
  DemandTrend.declining => (Icons.trending_down_rounded, Colors.red.shade700),
};

TextStyle _muted([double size = 11.5]) =>
    GoogleFonts.montserrat(fontSize: size, color: Colors.grey[600]);

/// One forecast line: "Tomato — High Demand — Rising", with the expected
/// top buyer area underneath and, on the full screen, a plain-words note
/// when the forecast rests on limited data.
class _ForecastRow extends StatelessWidget {
  final CommodityForecast item;
  final bool showConfidence;

  const _ForecastRow(this.item, {this.showConfidence = false});

  @override
  Widget build(BuildContext context) {
    final levelColor = _levelColor(item.demand);
    final (trendIcon, trendColor) = _trendStyle(item.trend);
    final area = item.topAreas.isEmpty ? '' : item.topAreas.first;
    final limited = item.confidence == ForecastConfidence.limited;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.commodity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                demandLevelLabel(item.demand),
                style: GoogleFonts.montserrat(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: levelColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  if (item.category.isNotEmpty) item.category,
                  if (area.isNotEmpty) 'Top expected area: $area',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _muted(),
              ),
            ),
            Icon(trendIcon, size: 15, color: trendColor),
            const SizedBox(width: 3),
            Text(
              demandTrendLabel(item.trend),
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: trendColor,
              ),
            ),
          ],
        ),
        if (showConfidence && limited)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Limited data — treat this as a rough guide.',
              style: _muted(11),
            ),
          ),
      ],
    );
  }
}

Widget _insufficient() => Text(
  kInsufficientForecastText,
  style: GoogleFonts.montserrat(
    fontSize: 12.5,
    color: Colors.grey[500],
    height: 1.4,
  ),
);

Widget _loadingBar() => ClipRRect(
  borderRadius: BorderRadius.circular(2),
  child: LinearProgressIndicator(
    minHeight: 2.5,
    color: AppTheme.dark.withValues(alpha: 0.55),
    backgroundColor: AppTheme.dark.withValues(alpha: 0.08),
  ),
);

/// Dashboard card: next month's top five expected commodities.
class DemandForecastCard extends StatefulWidget {
  const DemandForecastCard({super.key});

  /// How many commodities the dashboard card lists.
  static const int limit = 5;

  @override
  State<DemandForecastCard> createState() => _DemandForecastCardState();
}

class _DemandForecastCardState extends State<DemandForecastCard> {
  // Created once — not on every dashboard rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sales =
      FirebaseFirestore.instance.collection('market_sales').snapshots();

  @override
  Widget build(BuildContext context) {
    final month = DemandForecastService.nextMonth();
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
              const Icon(
                Icons.insights_outlined,
                size: 18,
                color: AppTheme.dark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Demand Forecast',
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
          Text(
            'Expected demand for ${DateFormat('MMMM y').format(month)}, '
            'estimated from completed orders across AgriTrade+',
            style: _muted(12),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sales,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError ? _insufficient() : _loadingBar();
              }
              return ListenableBuilder(
                listenable: CommodityRegistry.instance,
                builder: (context, _) {
                  final forecast = DemandForecastService.forecast(
                    sales: snapshot.data!.docs.map((d) => d.data()),
                    month: month,
                  );
                  if (forecast.insufficient) return _insufficient();
                  final items = forecast.items
                      .take(DemandForecastCard.limit)
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(height: 18, color: Colors.grey.shade200),
                        _ForecastRow(items[i]),
                      ],
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DemandForecastScreen(),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.dark,
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: GoogleFonts.montserrat(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('View Demand Forecast'),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Full Farmer view: pick one of the coming months and see every
/// commodity with a forecast, in plain terms.
class DemandForecastScreen extends StatefulWidget {
  const DemandForecastScreen({super.key});

  @override
  State<DemandForecastScreen> createState() => _DemandForecastScreenState();
}

class _DemandForecastScreenState extends State<DemandForecastScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sales =
      FirebaseFirestore.instance.collection('market_sales').snapshots();
  final List<DateTime> _months = DemandForecastService.upcomingMonths(6);
  late DateTime _month = _months.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Demand Forecast'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.dark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: AppTheme.heading(17).copyWith(color: AppTheme.dark),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _sales,
        builder: (context, snapshot) {
          final forecast = snapshot.hasData
              ? DemandForecastService.forecast(
                  sales: snapshot.data!.docs.map((d) => d.data()),
                  month: _month,
                )
              : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _months.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final month = _months[i];
                    final selected = month == _month;
                    return GestureDetector(
                      onTap: () => setState(() => _month = month),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.dark : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppTheme.dark
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          DateFormat('MMM y').format(month),
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expected demand · ${DateFormat('MMMM y').format(_month)}',
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (forecast == null)
                      snapshot.hasError ? _insufficient() : _loadingBar()
                    else if (forecast.insufficient)
                      _insufficient()
                    else
                      for (var i = 0; i < forecast.items.length; i++) ...[
                        if (i > 0)
                          Divider(height: 18, color: Colors.grey.shade200),
                        _ForecastRow(forecast.items[i], showConfidence: true),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This is an estimate based on completed orders across '
                'AgriTrade+ — recent demand, its trend and, where there is a '
                'year of history, the season. It is a guide, not a guarantee.',
                style: _muted(11),
              ),
            ],
          );
        },
      ),
    );
  }
}
