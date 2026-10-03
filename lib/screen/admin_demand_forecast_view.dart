import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import '../services/demand_forecast_service.dart';
import '../services/market_demand_service.dart';
import '../widgets/demand_forecast_views.dart';
import 'admin_dashboard_screen.dart'
    show AdminThemeScope, AdminPalette, AdminEmptyState, AdminLoadingSpinner;

/// Admin Portal → Demand Forecast: the full ranked forecast for a chosen
/// future month, with what it rests on (data availability / confidence).
/// The estimate itself is DemandForecastService's — the same one farmers
/// see a short version of — computed from completed orders only.
class AdminDemandForecastView extends StatefulWidget {
  const AdminDemandForecastView({super.key});

  @override
  State<AdminDemandForecastView> createState() =>
      _AdminDemandForecastViewState();
}

class _AdminDemandForecastViewState extends State<AdminDemandForecastView> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sales =
      FirebaseFirestore.instance.collection('market_sales').snapshots();
  final List<DateTime> _months = DemandForecastService.upcomingMonths(12);
  late DateTime _month = _months.first;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Demand Forecast',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expected commodity demand for a future month, estimated '
                      'from completed orders: recent demand, its trend and, with '
                      'a year of history, the season.',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: _month,
                    dropdownColor: c.surface,
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    items: [
                      for (final month in _months)
                        DropdownMenuItem(
                          value: month,
                          child: Text(DateFormat('MMMM y').format(month)),
                        ),
                    ],
                    onChanged: (month) {
                      if (month != null) setState(() => _month = month);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _sales,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return snapshot.hasError
                      ? const AdminEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load completed-order history',
                          subtitle:
                              'Check your connection and reopen this page.',
                        )
                      : const AdminLoadingSpinner();
                }
                // Rebuilt when the commodity list changes too — names and
                // categories come from it.
                return ListenableBuilder(
                  listenable: CommodityRegistry.instance,
                  builder: (context, _) => _table(
                    context,
                    DemandForecastService.forecast(
                      sales: snapshot.data!.docs.map((d) => d.data()),
                      month: _month,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, DemandForecast forecast) {
    final c = AdminThemeScope.of(context).palette;
    if (forecast.insufficient) {
      return const AdminEmptyState(
        icon: Icons.insights_outlined,
        title: kInsufficientForecastText,
        subtitle:
            'A forecast appears once there is enough completed-order history. '
            'Nothing is estimated from views, searches or pending orders.',
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
        dataRowColor: WidgetStateProperty.all(Colors.transparent),
        columnSpacing: 32,
        horizontalMargin: 12,
        headingTextStyle: TextStyle(
          color: c.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
        columns: const [
          DataColumn(label: Text('Rank')),
          DataColumn(label: Text('Commodity')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Forecasted Demand')),
          DataColumn(label: Text('Trend')),
          DataColumn(label: Text('Expected Top Buyer Locations')),
          DataColumn(label: Text('Order Type')),
          DataColumn(label: Text('Confidence')),
          DataColumn(label: Text('Data Availability')),
        ],
        rows: [
          for (var i = 0; i < forecast.items.length; i++)
            _row(c, i + 1, forecast.items[i]),
        ],
      ),
    );
  }

  DataRow _row(AdminPalette c, int rank, CommodityForecast item) {
    final secondary = TextStyle(color: c.textSecondary);
    final levelColor = switch (item.demand) {
      DemandLevel.high => c.green,
      DemandLevel.moderate => c.amber,
      _ => c.textSecondary,
    };
    final trendColor = switch (item.trend) {
      DemandTrend.rising => c.green,
      DemandTrend.declining => c.red,
      _ => c.textSecondary,
    };
    final confidenceColor = switch (item.confidence) {
      ForecastConfidence.high => c.green,
      ForecastConfidence.moderate => c.textPrimary,
      ForecastConfidence.limited => c.amber,
    };
    return DataRow(
      cells: [
        DataCell(Text('#$rank', style: secondary)),
        DataCell(
          Text(
            item.commodity,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(
          Text(item.category.isEmpty ? '—' : item.category, style: secondary),
        ),
        DataCell(
          Text(
            demandLevelLabel(item.demand),
            style: TextStyle(color: levelColor, fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(
          Text(
            demandTrendLabel(item.trend),
            style: TextStyle(color: trendColor),
          ),
        ),
        DataCell(
          Text(
            item.topAreas.isEmpty ? 'Not on record' : item.topAreas.join(', '),
            style: secondary,
          ),
        ),
        DataCell(
          Text(
            item.mostlyWholesale == null
                ? 'Mixed'
                : item.mostlyWholesale!
                ? 'Mostly Wholesale'
                : 'Mostly Retail',
            style: secondary,
          ),
        ),
        DataCell(
          Text(
            forecastConfidenceLabel(item.confidence),
            style: TextStyle(
              color: confidenceColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(
          Text(
            '${item.historyOrders} completed order${item.historyOrders == 1 ? '' : 's'} · '
            '${item.historyMonths} month${item.historyMonths == 1 ? '' : 's'}'
            '${item.seasonal ? ' · seasonal' : ''}',
            style: secondary,
          ),
        ),
      ],
    );
  }
}
