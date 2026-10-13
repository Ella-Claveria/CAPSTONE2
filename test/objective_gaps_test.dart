// The features added to close the gaps against the system objectives:
// the market change analysis and the Admin listings table.
import 'package:agritrade/screen/admin_listings_view.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:agritrade/services/market_diagnostics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 10);
Timestamp daysAgo(int days) =>
    Timestamp.fromDate(now.subtract(Duration(days: days)));

Map<String, dynamic> sale(int days, double price, double quantity) => {
  'status': 'completed',
  'productName': 'Rice',
  'unitPrice': price,
  'pricingType': 'retail',
  'quantity': quantity,
  'completedAt': daysAgo(days),
};

Map<String, dynamic> listing(
  double price,
  double stock, {
  int postedDaysAgo = 100,
}) => {
  'name': 'Rice',
  'retailPrice': price,
  'quantity': stock,
  'isArchived': false,
  'createdAt': daysAgo(postedDaysAgo),
};

MarketDiagnosis diagnose({
  List<HistoricalDemandRecord> historical = const [],
  List<Map<String, dynamic>> orders = const [],
  List<Map<String, dynamic>> products = const [],
}) => MarketDiagnosticsService.diagnose(
  commodity: 'Rice',
  historical: historical,
  completedOrders: orders,
  products: products,
  now: now,
);

void main() {
  group('market change analysis', () {
    test('nothing on record is reported as no data', () {
      final result = diagnose();
      expect(result.hasData, isFalse);
      expect(result.factors, isEmpty);
    });

    test('sales falling while listings sell out names that as a factor', () {
      final result = diagnose(
        orders: [sale(40, 50, 100), sale(5, 50, 40)],
        products: [listing(50, 10, postedDaysAgo: 45), listing(50, 0)],
      );
      expect(result.demand, ChangeDirection.down);
      expect(result.supply, ChangeDirection.down);
      expect(result.soldOutListings, 1);
      expect(
        result.factors.single,
        startsWith('Sales fell while supply tightened'),
      );
      expect(result.demandSummary, startsWith('Down 60%'));
    });

    test('prices rising with stock short of sales is named', () {
      final result = diagnose(
        orders: [sale(40, 50, 30), sale(5, 60, 30)],
        products: [listing(62, 10)],
      );
      expect(result.price, ChangeDirection.up);
      expect(result.currentMarketAverage, 62);
      expect(
        result.factors,
        contains(startsWith('Prices rose while supply tightened')),
      );
    });

    test('a change with nothing moving alongside it gets no invented '
        'reason', () {
      final result = diagnose(
        orders: [sale(40, 50, 100), sale(5, 50, 40)],
        products: [listing(50, 500)],
      );
      expect(result.demand, ChangeDirection.down);
      expect(result.factors, isEmpty);
    });

    test('a seasonal pattern is only cited when it matches the change', () {
      final history = [
        for (final year in [2024, 2025])
          for (var month = 1; month <= 12; month++)
            HistoricalDemandRecord(
              year: year,
              month: month,
              commodity: 'Rice',
              category: 'Grains',
              quantity: month == 10 ? 40 : 100,
              unit: 'kg',
            ),
      ];
      final falling = diagnose(
        historical: history,
        orders: [sale(40, 50, 100), sale(5, 50, 40)],
        products: [listing(50, 500)],
      );
      expect(falling.seasonalPattern, contains('October'));
      expect(falling.factors.single, startsWith('Seasonal pattern'));

      final rising = diagnose(
        historical: history,
        orders: [sale(40, 50, 40), sale(5, 50, 100)],
        products: [listing(50, 500)],
      );
      expect(rising.factors.where((f) => f.startsWith('Seasonal')), isEmpty);
    });

    test('only completed orders are counted', () {
      final result = diagnose(
        orders: [
          sale(5, 50, 10),
          {...sale(5, 50, 999), 'status': 'pending'},
          {...sale(5, 50, 999), 'productName': 'Corn'},
        ],
      );
      expect(result.soldLast30, 10);
      expect(result.ordersLast30, 1);
    });
  });

  group('product listings', () {
    final rows = buildListingRows([
      (
        id: 'p1',
        data: {
          'name': 'Tomato',
          'category': 'Vegetables',
          'farmerName': 'Mang Jose',
          'retailPrice': 40,
          'quantity': 25,
          'unit': 'kg',
          'createdAt': daysAgo(10),
        },
      ),
      (
        id: 'p2',
        data: {
          'name': 'Rice',
          'category': 'Grains',
          'price': 50,
          'wholesaleEnabled': true,
          'wholesalePrice': 45,
          'quantity': 0,
          'createdAt': daysAgo(2),
        },
      ),
      (id: 'p3', data: {'name': 'Corn', 'quantity': 5, 'isArchived': true}),
      (
        id: 'p4',
        data: {
          'name': 'Okra',
          'quantity': 5,
          'isArchived': true,
          'isSuspended': true,
        },
      ),
    ]);
    AdminListingRow row(String id) => rows.firstWhere((r) => r.id == id);

    test('every listing is shown, newest first', () {
      expect(rows.map((r) => r.id), ['p2', 'p1', 'p3', 'p4']);
    });

    test('status follows stock, archive and admin hiding', () {
      expect(row('p1').status, ListingStatus.active);
      expect(row('p2').status, ListingStatus.soldOut);
      expect(row('p3').status, ListingStatus.archived);
      expect(row('p4').status, ListingStatus.suspended);
    });

    test(
      'a listing marked removed is hidden, and restoration respects archive and stock',
      () {
        final removed = {
          'isSuspended': true,
          'moderationStatus': 'removed',
          'quantity': 10,
        };
        expect(
          AdminListingRow.fromProduct('removed', removed).status,
          ListingStatus.suspended,
        );
        expect(
          AdminListingRow.fromProduct('restored', {
            ...removed,
            'isSuspended': false,
            'moderationStatus': 'restored',
          }).status,
          ListingStatus.active,
        );
        expect(
          AdminListingRow.fromProduct('archived', {
            ...removed,
            'isSuspended': false,
            'isArchived': true,
          }).status,
          ListingStatus.archived,
        );
        expect(
          AdminListingRow.fromProduct('empty', {
            ...removed,
            'isSuspended': false,
            'quantity': 0,
          }).status,
          ListingStatus.soldOut,
        );
      },
    );

    test("prices are the listing's own; wholesale only when offered", () {
      expect(row('p1').price, 40);
      expect(row('p1').wholesalePrice, isNull);
      expect(row('p2').price, 50);
      expect(row('p2').wholesalePrice, 45);
      expect(row('p3').price, isNull);
    });

    test('search covers product, farmer and category', () {
      expect(rows.where((r) => r.matches('jose')).single.id, 'p1');
      expect(rows.where((r) => r.matches('grains')).single.id, 'p2');
      expect(rows.where((r) => r.matches('')).length, 4);
    });
  });
}
