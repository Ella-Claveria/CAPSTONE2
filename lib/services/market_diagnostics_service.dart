import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../data/commodity_master_list.dart';
import 'historical_demand_service.dart';
import 'market_price_helpers.dart';

/// DIAGNOSTIC ANALYTICS for one commodity: what changed in its demand,
/// supply and price over the last 30 days against the 30 days before, and
/// which possible factors the data itself points to.
///
/// Everything is read from records that exist:
///  * demand — quantity in orders with status `completed`;
///  * supply — the marketplace's listings: how many are on sale, their
///    stock, how many were posted, sold out or archived;
///  * price — what buyers paid in completed retail orders, and what active
///    listings ask now (the Current Market Average);
///  * season — the Admin's imported `historical_demand` records for this
///    calendar month in previous years.
///
/// A possible factor is only stated when two of these moved together in
/// the data (sales fell while listings sold out, prices rose while stock
/// ran short, ...). Where nothing lines up, that is said; a reason is
/// never supplied without data behind it.

enum ChangeDirection { up, steady, down, unknown }

class MarketDiagnosis {
  final String commodity;
  final String unit;

  /// False when the commodity has no listing, completed order or imported
  /// record at all.
  final bool hasData;

  // ---- Demand: completed orders. ----
  final double soldLast30;
  final double soldPrevious30;
  final int ordersLast30;
  final int ordersPrevious30;
  final ChangeDirection demand;
  final String demandSummary;

  // ---- Supply: listings and stock. ----
  final int activeListings;
  final double availableStock;
  final int addedLast30;
  final int addedPrevious30;
  final int soldOutListings;
  final int archivedLast30;
  final ChangeDirection supply;
  final String supplySummary;

  // ---- Price. ----
  final double? paidLast30;
  final double? paidPrevious30;
  final double? currentMarketAverage;
  final int pricedListings;
  final ChangeDirection price;
  final String priceSummary;

  /// This calendar month in the imported records, in words; empty when the
  /// month is not on record.
  final String seasonalPattern;

  /// Possible factors behind the changes, each backed by the figures
  /// above. Empty when the data points to none.
  final List<String> factors;

  const MarketDiagnosis({
    required this.commodity,
    required this.unit,
    required this.hasData,
    required this.soldLast30,
    required this.soldPrevious30,
    required this.ordersLast30,
    required this.ordersPrevious30,
    required this.demand,
    required this.demandSummary,
    required this.activeListings,
    required this.availableStock,
    required this.addedLast30,
    required this.addedPrevious30,
    required this.soldOutListings,
    required this.archivedLast30,
    required this.supply,
    required this.supplySummary,
    required this.paidLast30,
    required this.paidPrevious30,
    required this.currentMarketAverage,
    required this.pricedListings,
    required this.price,
    required this.priceSummary,
    required this.seasonalPattern,
    required this.factors,
  });
}

class MarketDiagnosticsService {
  const MarketDiagnosticsService._();

  /// A change in quantity sold beyond this, either way, is a change.
  static const double demandThreshold = 0.10;

  /// A change in price paid beyond this, either way, is a change.
  static const double priceThreshold = 0.05;

  static DateTime? _date(dynamic value) =>
      value is Timestamp ? value.toDate() : (value is DateTime ? value : null);

  static double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static bool _isCommodity(Map<String, dynamic> record, String commodity) {
    final name = (record['productName'] ?? record['name'] ?? '').toString();
    if (name.trim().isEmpty) return false;
    return (matchSupportedCommodity(name) ?? name.trim()).toLowerCase() ==
        commodity.toLowerCase();
  }

  static double _mean(Iterable<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static String _percent(double ratio) => '${(ratio.abs() * 100).round()}%';

  static String _plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

  static MarketDiagnosis diagnose({
    required String commodity,
    required Iterable<HistoricalDemandRecord> historical,
    required Iterable<Map<String, dynamic>> completedOrders,
    required Iterable<Map<String, dynamic>> products,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final last30 = today.subtract(const Duration(days: 30));
    final last60 = today.subtract(const Duration(days: 60));
    final unit = unitForCommodity(commodity);
    String amount(double value) => formatStock(value, unit);
    String money(double value) => formatPriceWithUnit(value, unit);

    // ---- Completed orders: quantity, and retail price paid. ----
    var sold = 0.0, soldBefore = 0.0;
    var orders = 0, ordersBefore = 0, everSold = 0;
    final paid = <double>[], paidBefore = <double>[];
    for (final order in completedOrders) {
      if ((order['status'] ?? '').toString().toLowerCase() != 'completed') {
        continue;
      }
      if (!_isCommodity(order, commodity)) continue;
      final date =
          _date(order['completedAt']) ??
          _date(order['updatedAt']) ??
          _date(order['createdAt']);
      if (date == null || date.isAfter(today)) continue;
      everSold++;
      final recent = date.isAfter(last30);
      if (!recent && !date.isAfter(last60)) continue;
      final quantity = _number(order['quantity']);
      final unitPrice = _number(order['unitPrice'] ?? order['pricePerUnit']);
      final retail =
          (order['pricingType'] ?? 'retail').toString().toLowerCase() ==
          'retail';
      if (recent) {
        sold += quantity;
        orders++;
        if (retail && unitPrice > 0) paid.add(unitPrice);
      } else {
        soldBefore += quantity;
        ordersBefore++;
        if (retail && unitPrice > 0) paidBefore.add(unitPrice);
      }
    }

    // ---- Listings. ----
    var listings = 0, active = 0, added = 0, addedBefore = 0;
    var soldOut = 0, archived = 0;
    var stock = 0.0;
    final asking = <double>[];
    for (final product in products) {
      if (product['isSuspended'] == true) continue;
      if (!_isCommodity(product, commodity)) continue;
      listings++;
      final created = _date(product['createdAt']);
      if (created != null) {
        if (created.isAfter(last30)) {
          added++;
        } else if (created.isAfter(last60)) {
          addedBefore++;
        }
      }
      if (product['isArchived'] == true) {
        final archivedAt = _date(product['archivedAt']);
        if (archivedAt != null && archivedAt.isAfter(last30)) archived++;
        continue;
      }
      final quantity = _number(product['quantity']);
      if (quantity <= 0) {
        soldOut++;
        continue;
      }
      active++;
      stock += quantity;
      final price = _number(product['retailPrice'] ?? product['price']);
      if (price > 0) asking.add(price);
    }

    // ---- This calendar month in the imported records. ----
    final nowKey = today.year * 12 + today.month - 1;
    final bySource = <int, Map<String, double>>{};
    for (final record in historical) {
      if (record.commodity.toLowerCase() != commodity.toLowerCase()) continue;
      final key = record.year * 12 + record.month - 1;
      if (key >= nowKey) continue;
      final sources = bySource.putIfAbsent(key, () => {});
      sources[record.source] = (sources[record.source] ?? 0) + record.quantity;
    }
    final hist = {
      for (final entry in bySource.entries)
        entry.key: _mean(entry.value.values),
    };
    final sameMonth = [
      for (final entry in hist.entries)
        if (entry.key % 12 + 1 == today.month) entry.value,
    ];
    final monthName = DateFormat('MMMM').format(today);
    double? seasonalIndex;
    var seasonalPattern = '';
    if (sameMonth.isNotEmpty && _mean(hist.values) > 0) {
      seasonalIndex = _mean(sameMonth) / _mean(hist.values) - 1;
      final years = _plural(sameMonth.length, 'previous year');
      seasonalPattern = seasonalIndex.abs() < 0.05
          ? 'In $years on record, $monthName was about the same as this '
                'commodity\'s average month (imported historical data).'
          : 'In $years on record, $monthName was '
                '${_percent(seasonalIndex)} '
                '${seasonalIndex > 0 ? 'above' : 'below'} this commodity\'s '
                'average month (imported historical data).';
    }

    // ---- Demand. ----
    final double? demandChange = soldBefore > 0 ? sold / soldBefore - 1 : null;
    final ChangeDirection demand;
    final String demandSummary;
    if (sold == 0 && soldBefore == 0) {
      demand = ChangeDirection.unknown;
      demandSummary = everSold == 0
          ? 'No completed orders of this commodity yet.'
          : 'No completed orders in the last 60 days.';
    } else if (demandChange == null) {
      demand = ChangeDirection.up;
      demandSummary =
          '${amount(sold)} sold in ${_plural(orders, 'completed order')} in '
          'the last 30 days; none in the 30 before.';
    } else {
      demand = demandChange > demandThreshold
          ? ChangeDirection.up
          : demandChange < -demandThreshold
          ? ChangeDirection.down
          : ChangeDirection.steady;
      demandSummary =
          '${demand == ChangeDirection.steady ? 'Steady' : '${demand == ChangeDirection.up ? 'Up' : 'Down'} ${_percent(demandChange)}'} '
          '— ${amount(sold)} sold in ${_plural(orders, 'completed order')} '
          'in the last 30 days against ${amount(soldBefore)} in '
          '$ordersBefore in the 30 before.';
    }

    // ---- Supply. ----
    final leaving = soldOut + archived;
    final shortOfSales = sold > 0 && stock < sold;
    final ampleStock = sold > 0 && stock >= sold * 2;
    final supplyVotes =
        added.compareTo(addedBefore) +
        (shortOfSales ? -1 : (ampleStock ? 1 : 0)) +
        (leaving > added ? -1 : 0);
    final ChangeDirection supply = listings == 0
        ? ChangeDirection.unknown
        : supplyVotes > 0
        ? ChangeDirection.up
        : supplyVotes < 0
        ? ChangeDirection.down
        : ChangeDirection.steady;
    final supplySummary = listings == 0
        ? 'No listing of this commodity on the marketplace.'
        : '${amount(stock)} available across '
              '${_plural(active, 'active listing')}; '
              '$added posted in the last 30 days ($addedBefore in the 30 '
              'before); $soldOut sold out, $archived archived in the last '
              '30 days.';

    // ---- Price. ----
    final paidNow = paid.isEmpty ? null : _mean(paid);
    final paidThen = paidBefore.isEmpty ? null : _mean(paidBefore);
    final marketAverage = asking.isEmpty ? null : _mean(asking);
    final double? priceChange = paidNow != null && paidThen != null
        ? paidNow / paidThen - 1
        : null;
    final ChangeDirection price = priceChange == null
        ? ChangeDirection.unknown
        : priceChange > priceThreshold
        ? ChangeDirection.up
        : priceChange < -priceThreshold
        ? ChangeDirection.down
        : ChangeDirection.steady;
    final averagePart = marketAverage == null
        ? 'No active listing to average.'
        : 'Current Market Average ${money(marketAverage)} across '
              '${_plural(asking.length, 'active listing')}.';
    final String paidPart;
    if (priceChange != null) {
      paidPart =
          '${price == ChangeDirection.steady ? 'Steady' : '${price == ChangeDirection.up ? 'Up' : 'Down'} ${_percent(priceChange)}'} '
          '— buyers paid ${money(paidNow!)} on average in the last 30 days '
          'against ${money(paidThen!)} in the 30 before. ';
    } else if (paidNow != null) {
      paidPart =
          'Buyers paid ${money(paidNow)} on average in the last 30 days; '
          'no sales in the 30 before to compare with. ';
    } else {
      paidPart = 'No completed retail sales in the last 30 days. ';
    }

    // ---- Possible factors: only where the figures moved together. ----
    final tightening = supply == ChangeDirection.down;
    final growing = supply == ChangeDirection.up;
    final supplyFacts = [
      if (soldOut > 0) '${_plural(soldOut, 'listing')} sold out',
      if (archived > 0) '$archived archived',
      if (added < addedBefore)
        '$added new ${added == 1 ? 'listing' : 'listings'} against '
            '$addedBefore before',
      if (shortOfSales)
        'available stock (${amount(stock)}) is less than what sold in the '
            'last 30 days',
    ].join(', ');
    final factors = <String>[
      if (demand == ChangeDirection.down && tightening)
        'Sales fell while supply tightened ($supplyFacts) — limited '
            'availability may have held sales back.',
      if (demand == ChangeDirection.down && price == ChangeDirection.up)
        'Sales fell as the average price paid rose '
            '${_percent(priceChange!)}.',
      if (demand == ChangeDirection.up && price == ChangeDirection.down)
        'Sales rose as the average price paid fell '
            '${_percent(priceChange!)}.',
      if (price == ChangeDirection.up && tightening)
        'Prices rose while supply tightened ($supplyFacts).',
      if (price == ChangeDirection.down && growing)
        'Prices fell while supply grew ($added new '
            '${added == 1 ? 'listing' : 'listings'} against $addedBefore '
            'before, ${amount(stock)} available).',
      if (demand == ChangeDirection.up && growing)
        'Sales rose as more supply became available ($added new '
            '${added == 1 ? 'listing' : 'listings'} against $addedBefore '
            'before).',
      if (seasonalIndex != null &&
          seasonalIndex.abs() >= demandThreshold &&
          ((seasonalIndex > 0 && demand == ChangeDirection.up) ||
              (seasonalIndex < 0 && demand == ChangeDirection.down)))
        'Seasonal pattern: in previous years $monthName was '
            '${_percent(seasonalIndex)} '
            '${seasonalIndex > 0 ? 'above' : 'below'} the average month, '
            'in line with this change.',
    ];

    return MarketDiagnosis(
      commodity: commodity,
      unit: unit,
      hasData: listings > 0 || everSold > 0 || hist.isNotEmpty,
      soldLast30: sold,
      soldPrevious30: soldBefore,
      ordersLast30: orders,
      ordersPrevious30: ordersBefore,
      demand: demand,
      demandSummary: demandSummary,
      activeListings: active,
      availableStock: stock,
      addedLast30: added,
      addedPrevious30: addedBefore,
      soldOutListings: soldOut,
      archivedLast30: archived,
      supply: supply,
      supplySummary: supplySummary,
      paidLast30: paidNow,
      paidPrevious30: paidThen,
      currentMarketAverage: marketAverage,
      pricedListings: asking.length,
      price: price,
      priceSummary: '$paidPart$averagePart',
      seasonalPattern: seasonalPattern,
      factors: factors,
    );
  }
}
