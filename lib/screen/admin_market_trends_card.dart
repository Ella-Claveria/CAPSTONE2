import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/admin_perf.dart';
import '../services/dashboard_data_service.dart';
import '../services/historical_demand_service.dart';
import '../services/market_diagnostics_service.dart';
import 'admin_analytics_widgets.dart'
    show AdminCommoditySearchField, matchCommodities;
import 'admin_dashboard_screen.dart'
    show
        AdminThemeScope,
        AdminPalette,
        AdminEmptyState,
        AdminLoadingSpinner,
        AdminQuickActionButton,
        AdminRadii;
import 'historical_demand_import.dart';

/// Analytics Dashboard → Market Trends: for one commodity, what changed in
/// its demand, local supply and price over the last 30 days against the 30
/// before, how this month compared in previous years, and the possible
/// factors the data points to (see [MarketDiagnosticsService]).
///
/// Read from AgriTrade+ completed orders and listings (the portal's shared
/// live data) and the Admin's imported historical demand, which is
/// imported from here too. Nothing is forecast.
class AdminMarketTrendsCard extends StatefulWidget {
  const AdminMarketTrendsCard({super.key});

  @override
  State<AdminMarketTrendsCard> createState() => _AdminMarketTrendsCardState();
}

class _AdminMarketTrendsCardState extends State<AdminMarketTrendsCard> {
  late final Stream<List<HistoricalDemandRecord>> _historical =
      AdminPerf.firstEvent(
        'market trends: historical_demand stream',
        HistoricalDemandService.watch(),
        describe: (records) => '${records.length} records',
      );

  String? _commodity;

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      // Rebuilt when the commodity list, the orders or the listings change.
      child: ListenableBuilder(
        listenable: Listenable.merge([
          CommodityRegistry.instance,
          DashboardDataService.instance,
        ]),
        builder: (context, _) {
          final names = matchCommodities([
            for (final commodity in CommodityRegistry.instance.all)
              commodity.name,
          ], '');
          if (_commodity == null || !names.contains(_commodity)) {
            _commodity = names.isEmpty ? null : names.first;
          }
          final commodity = _commodity;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full width, so the title sits on the left and the controls on
              // the right, as on the other cards.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Market Change Analysis',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          commodity == null
                              ? 'Last 30 days against the 30 days before'
                              : '$commodity · last 30 days against the 30 '
                                    'days before',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (names.isNotEmpty)
                          AdminCommoditySearchField(
                            key: ValueKey(commodity),
                            commodities: names,
                            selected: commodity,
                            onSelected: (name) =>
                                setState(() => _commodity = name),
                          ),
                        const SizedBox(width: 12),
                        AdminQuickActionButton(
                          icon: Icons.upload_file_outlined,
                          label: 'Import Historical Data',
                          onPressed: () => showHistoricalDemandImport(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (commodity == null)
                const AdminEmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No supported commodities yet',
                  subtitle: 'Add commodities in Price Management first.',
                )
              else
                StreamBuilder<List<HistoricalDemandRecord>>(
                  stream: _historical,
                  builder: (context, historical) {
                    final data = DashboardDataService.instance;
                    if (!data.hasLoadedOnce && data.lastError == null) {
                      return const AdminLoadingSpinner();
                    }
                    if (!historical.hasData && !historical.hasError) {
                      return const AdminLoadingSpinner();
                    }
                    return _analysis(
                      c,
                      MarketDiagnosticsService.diagnose(
                        commodity: commodity,
                        historical: historical.data ?? const [],
                        completedOrders: [
                          for (final d in data.orders) d.data(),
                        ],
                        products: [for (final d in data.products) d.data()],
                      ),
                      historicalMissing: historical.hasError,
                      liveMissing: !data.hasLoadedOnce,
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _analysis(
    AdminPalette c,
    MarketDiagnosis d, {
    required bool historicalMissing,
    required bool liveMissing,
  }) {
    final notices = [
      if (historicalMissing)
        'Imported historical data could not be loaded, so it is not '
            'included here.',
      if (liveMissing)
        'Orders and listings could not be loaded, so they are not included '
            'here.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: c.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notice,
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        if (!d.hasData)
          const AdminEmptyState(
            icon: Icons.insights_outlined,
            title: 'No data for this commodity yet',
            subtitle:
                'It has no listing, completed order or imported record to '
                'analyze.',
          )
        else ...[
          _tiles(c, d),
          const SizedBox(height: 14),
          _detail(c, 'Demand', d.demandSummary),
          _detail(c, 'Local Supply', d.supplySummary),
          _detail(c, 'Market Price', d.priceSummary),
          if (d.seasonalPattern.isNotEmpty)
            _detail(c, 'Seasonal Pattern', d.seasonalPattern),
          _detail(
            c,
            'Possible Factors',
            d.factors.isEmpty
                ? 'The data on record points to no specific factor behind '
                      'these changes.'
                : d.factors.map((f) => '• $f').join('\n'),
            last: true,
          ),
        ],
      ],
    );
  }

  // The three changes at a glance. For price, a rise is the caution colour.
  Widget _tiles(AdminPalette c, MarketDiagnosis d) {
    String word(ChangeDirection direction, String up, String down) =>
        switch (direction) {
          ChangeDirection.up => up,
          ChangeDirection.down => down,
          ChangeDirection.steady => 'Steady',
          ChangeDirection.unknown => 'Nothing to compare yet',
        };
    Color tone(ChangeDirection direction, {bool upIsGood = true}) =>
        switch (direction) {
          ChangeDirection.up => upIsGood ? c.green : c.amber,
          ChangeDirection.down => upIsGood ? c.red : c.green,
          _ => c.textSecondary,
        };
    final tiles = [
      (
        label: 'Demand',
        value: word(d.demand, 'Increased', 'Decreased'),
        color: tone(d.demand),
      ),
      (
        label: 'Local Supply',
        value: word(d.supply, 'Increased', 'Decreased'),
        color: tone(d.supply),
      ),
      (
        label: 'Market Price',
        value: word(d.price, 'Increased', 'Decreased'),
        color: tone(d.price, upIsGood: false),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    c.green.withValues(alpha: c.isDark ? 0.08 : 0.05),
                    c.surface,
                  ),
                  borderRadius: BorderRadius.circular(AdminRadii.card),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tile.label,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tile.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tile.color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _detail(
    AdminPalette c,
    String label,
    String value, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: c.textPrimary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
