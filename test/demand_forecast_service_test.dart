import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/demand_forecast_service.dart';
import 'package:agritrade/services/market_demand_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(
  String product,
  DateTime date, {
  String area = 'Tanauan City',
  String pricing = 'retail',
  String status = 'completed',
}) => {
  'productName': product,
  'status': status,
  'unit': 'kg',
  'buyerArea': area,
  'pricingType': pricing,
  'completedAt': Timestamp.fromDate(date),
};

void main() {
  final now = DateTime(2026, 10, 20);
  final november = DateTime(2026, 11);
  DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  /// [count] sales spread evenly from [from] to [to] days ago.
  List<Map<String, dynamic>> spread(
    String product,
    int count, {
    required int from,
    required int to,
    String area = 'Tanauan City',
    String pricing = 'retail',
  }) => [
    for (var i = 0; i < count; i++)
      _sale(
        product,
        daysAgo(
          from - ((from - to) * i / (count == 1 ? 1 : count - 1)).round(),
        ),
        area: area,
        pricing: pricing,
      ),
  ];

  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  DemandForecast run(List<Map<String, dynamic>> sales, {DateTime? month}) =>
      DemandForecastService.forecast(
        sales: sales,
        month: month ?? november,
        now: now,
      );

  test('too little history: no forecast is made up', () {
    expect(run(const []).insufficient, isTrue);
    final few = run(spread('Tomato', 6, from: 40, to: 2));
    expect(few.insufficient, isTrue);
    expect(few.items, isEmpty);
  });

  test('ranks by recent completed orders; level is relative to the top', () {
    final forecast = run([
      ...spread('Fresh Tomato', 18, from: 88, to: 1),
      ...spread('Eggplant', 9, from: 88, to: 1, area: 'Laurel'),
      ...spread('Banana', 3, from: 88, to: 1),
      // Never counted: not completed, or not happened yet.
      ...List.generate(20, (_) => _sale('Okra', daysAgo(5), status: 'pending')),
      _sale('Squash', now.add(const Duration(days: 3))),
    ]);

    expect(forecast.insufficient, isFalse);
    expect(forecast.month, november);
    expect(forecast.items.map((i) => i.commodity), [
      'Tomato',
      'Eggplant',
      'Banana',
    ]);
    // The Admin-added commodity is forecast, with its category.
    expect(forecast.items[0].category, 'Vegetables');
    expect(forecast.items.map((i) => i.demand), [
      DemandLevel.high,
      DemandLevel.moderate,
      DemandLevel.low,
    ]);
    expect(forecast.items[0].topAreas, ['Tanauan City']);
    expect(forecast.items[1].topAreas, ['Laurel']);
  });

  test('trend follows the last 30 days against the 30 before', () {
    final trends = {
      for (final item in run([
        // 8 in the last 30 days vs 2 before → Rising.
        ...spread('Tomato', 8, from: 28, to: 1),
        ...spread('Tomato', 2, from: 55, to: 35),
        // 4 vs 4 → Stable.
        ...spread('Eggplant', 4, from: 28, to: 1),
        ...spread('Eggplant', 4, from: 58, to: 32),
        // 1 vs 6 → Declining.
        ...spread('Banana', 1, from: 10, to: 10),
        ...spread('Banana', 6, from: 58, to: 32),
      ]).items)
        item.commodity: item.trend,
    };
    expect(trends, {
      'Tomato': DemandTrend.rising,
      'Eggplant': DemandTrend.stable,
      'Banana': DemandTrend.declining,
    });
  });

  test('confidence reflects how much history there is', () {
    final forecast = run([
      // Three orders in one month: forecastable, but only just.
      ...spread('Banana', 3, from: 20, to: 2),
      // A dozen over four months.
      ...spread('Eggplant', 12, from: 110, to: 2),
      // Well over a year of steady sales.
      ...spread('Tomato', 60, from: 560, to: 1),
    ]);
    final confidence = {
      for (final item in forecast.items) item.commodity: item.confidence,
    };
    expect(confidence, {
      'Tomato': ForecastConfidence.high,
      'Eggplant': ForecastConfidence.moderate,
      'Banana': ForecastConfidence.limited,
    });
    expect(
      forecast.items.firstWhere((i) => i.commodity == 'Tomato').seasonal,
      isTrue,
    );
  });

  test('far-ahead months without seasonal history stay low-confidence', () {
    final sales = spread('Eggplant', 12, from: 110, to: 2);
    expect(run(sales).items.single.confidence, ForecastConfidence.moderate);
    expect(
      run(sales, month: DateTime(2027, 4)).items.single.confidence,
      ForecastConfidence.limited,
    );
  });

  test('a seasonal peak a year earlier lifts that month\'s forecast', () {
    final steady = spread('Eggplant', 40, from: 560, to: 1);
    final seasonal = [
      ...spread('Tomato', 40, from: 560, to: 1),
      // A burst of Tomato orders in December 2025.
      for (var day = 1; day <= 20; day++)
        _sale('Tomato', DateTime(2025, 12, day)),
    ];
    final december = run([...steady, ...seasonal], month: DateTime(2026, 12));
    final november = run([...steady, ...seasonal]);

    DemandLevel level(DemandForecast f, String name) =>
        f.items.firstWhere((i) => i.commodity == name).demand;
    // In December, Tomato pulls clearly ahead of the equally steady
    // Eggplant; in November the two are level.
    expect(december.items.first.commodity, 'Tomato');
    expect(level(december, 'Eggplant'), isNot(DemandLevel.high));
    expect(level(november, 'Eggplant'), DemandLevel.high);
  });

  test('order type is only named when one clearly dominates', () {
    final forecast = run([
      ...spread('Tomato', 10, from: 60, to: 1, pricing: 'wholesale'),
      ...spread('Eggplant', 5, from: 60, to: 1),
      ...spread('Eggplant', 5, from: 59, to: 2, pricing: 'wholesale'),
    ]);
    final type = {
      for (final item in forecast.items) item.commodity: item.mostlyWholesale,
    };
    expect(type, {'Tomato': true, 'Eggplant': null});
  });
}
