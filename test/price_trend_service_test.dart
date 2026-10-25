import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:agritrade/services/price_trend_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp _on(int year, int month, [int day = 10]) =>
    Timestamp.fromDate(DateTime(year, month, day));

void main() {
  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  test('year pairs start at 2025 against 2026, one more each year', () {
    expect(PriceTrendService.yearPairs(DateTime(2026, 10)), [
      (previous: 2025, current: 2026),
    ]);
    expect(PriceTrendService.yearPairs(DateTime(2028, 1)), [
      (previous: 2025, current: 2026),
      (previous: 2026, current: 2027),
      (previous: 2027, current: 2028),
    ]);
  });

  test('every price on record for the commodity counts, from all four '
      'sources, in the month of its own date', () {
    final points = PriceTrendService.collect(
      commodity: 'Tomato',
      products: [
        // A listing named after the commodity, last edited in March 2026.
        {
          'name': 'Fresh Native Tomato',
          'unit': 'kg',
          'retailPrice': 60,
          'createdAt': _on(2026, 1),
          'updatedAt': _on(2026, 3),
        },
        // Another commodity: not counted.
        {'name': 'Eggplant', 'retailPrice': 40, 'createdAt': _on(2026, 3)},
      ],
      completedOrders: [
        {
          'productName': 'Tomato',
          'unit': 'kg',
          'pricingType': 'retail',
          'pricePerUnit': 80,
          'completedAt': _on(2026, 3),
        },
        // Wholesale is a bulk discount, not the market price.
        {
          'productName': 'Tomato',
          'unit': 'kg',
          'pricingType': 'wholesale',
          'pricePerUnit': 30,
          'completedAt': _on(2026, 3),
        },
        // Another unit never mixes in.
        {
          'productName': 'Tomato',
          'unit': 'crate',
          'pricingType': 'retail',
          'pricePerUnit': 900,
          'completedAt': _on(2026, 3),
        },
      ],
      referenceHistory: [
        {'price': 50, 'unit': 'kg', 'effectiveDate': _on(2025, 3)},
      ],
      historical: const [
        HistoricalDemandRecord(
          year: 2025,
          month: 3,
          commodity: 'Tomato',
          category: 'Vegetables',
          quantity: 100,
          unit: 'kg',
          averagePrice: 70,
        ),
      ],
    );

    expect(points.map((p) => p.source).toSet(), {
      PriceTrendSource.farmerListing,
      PriceTrendSource.farmerSale,
      PriceTrendSource.adminReference,
      PriceTrendSource.adminImport,
    });
    expect(points, hasLength(4));

    final y2025 = PriceTrendService.monthlyAverages(points, 2025);
    final y2026 = PriceTrendService.monthlyAverages(points, 2026);
    // March: (50 + 70) / 2 in 2025, (60 + 80) / 2 in 2026.
    expect(y2025[2], 60);
    expect(y2026[2], 70);
    // The listing counts when it was last edited, not when first posted.
    expect(y2026[0], isNull);
  });

  test('a month with no price is a gap, never a zero', () {
    final points = [
      PriceTrendPoint(DateTime(2026, 1, 5), 100, PriceTrendSource.farmerSale),
      PriceTrendPoint(DateTime(2026, 4, 5), 120, PriceTrendSource.farmerSale),
    ];
    final monthly = PriceTrendService.monthlyAverages(points, 2026);
    expect(monthly[0], 100);
    expect(monthly[1], isNull);
    expect(monthly[3], 120);
    expect(PriceTrendService.yearAverage(monthly), 110);
    expect(
      PriceTrendService.yearAverage(
        PriceTrendService.monthlyAverages(points, 2025),
      ),
      isNull,
    );
  });
}
