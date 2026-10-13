// The Admin Demand Heatmap's data: completed purchases counted per buyer
// area for one month — the buyer's location, never the seller's, and never
// a buyer's exact pin.
// ignore_for_file: subtype_of_sealed_class
import 'package:agritrade/data/laurel_barangays.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

class OrderDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;
  OrderDoc(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;
}

var _nextId = 0;

/// A completed order by [buyerId], completed on [day] of October 2026.
OrderDoc order(String buyerId, int day, {int month = 10, num total = 100}) =>
    OrderDoc('o${_nextId++}', {
      'status': 'completed',
      'buyerId': buyerId,
      // The seller's details are on the order too, and must not matter.
      'farmerId': 'farmer-far-away',
      'total': total,
      'completedAt': Timestamp.fromDate(DateTime(2026, month, day)),
    });

void main() {
  // Two buyers a few hundred metres apart in the same Laurel barangay, one
  // in another barangay, one in Tanauan, and one with no location at all.
  final users = <String, Map<String, dynamic>>{
    'ana': {
      'barangay': 'Bugaan East',
      'municipality': 'Laurel',
      'latitude': kLaurelCenterLat + 0.0031,
      'longitude': kLaurelCenterLng + 0.0012,
    },
    'ben': {
      'barangay': 'Bugaan East',
      'municipality': 'Laurel',
      'latitude': kLaurelCenterLat + 0.0048,
      'longitude': kLaurelCenterLng + 0.0027,
    },
    'cora': {
      'barangay': 'Leviste',
      'municipality': 'Laurel',
      'latitude': kLaurelCenterLat - 0.0213,
      'longitude': kLaurelCenterLng - 0.0174,
    },
    'dan': {
      'barangay': 'Poblacion',
      'municipality': 'Tanauan',
      'latitude': 14.0863,
      'longitude': 121.1497,
    },
    'eve': <String, dynamic>{},
    'fay': {'barangay': 'Sambat', 'municipality': 'Tanauan'},
  };

  final orders = [
    order('ana', 2),
    order('ana', 9),
    order('ben', 5),
    order('cora', 7),
    order('dan', 3),
    order('eve', 4), // no saved location: cannot be mapped
    // Saved an address from the list, with no map pin.
    order('fay', 6),
    order('fay', 8),
    order('ana', 20, month: 9), // another month
  ];

  final demand = DashboardAnalyticsService.demandByBuyerAreaForMonth(
    orders,
    users,
    year: 2026,
    month: 10,
  );

  test('counts completed purchases per buyer area, highest first', () {
    expect(demand.map((d) => (d.area, d.orderCount)), [
      ('Bugaan East, Laurel', 3),
      ('Sambat, Tanauan', 2),
      ('Leviste, Laurel', 1),
      ('Poblacion, Tanauan', 1),
    ]);
    expect(demand.first.revenue, 300);
  });

  test('only the selected month counts', () {
    final september = DashboardAnalyticsService.demandByBuyerAreaForMonth(
      orders,
      users,
      year: 2026,
      month: 9,
    );
    expect(september.map((d) => (d.area, d.orderCount)), [
      ('Bugaan East, Laurel', 1),
    ]);
    expect(
      DashboardAnalyticsService.demandByBuyerAreaForMonth(
        orders,
        users,
        year: 2026,
        month: 8,
      ),
      isEmpty,
    );
  });

  test('an area is one general point — never a buyer\'s exact pin', () {
    for (final area in demand) {
      for (final user in users.values) {
        if (user['latitude'] == null) continue;
        expect(
          area.lat == user['latitude'] && area.lng == user['longitude'],
          isFalse,
          reason: '${area.area} is plotted at an exact buyer pin',
        );
      }
    }
    // Still in the right place: within about a kilometre of its buyers.
    final bugaan = demand.first;
    expect(bugaan.lat, closeTo(kLaurelCenterLat + 0.004, 0.01));
    expect(bugaan.lng, closeTo(kLaurelCenterLng + 0.002, 0.01));
    final tanauan = demand.last;
    expect(tanauan.lat, closeTo(14.09, 0.001));
    expect(tanauan.lng, closeTo(121.15, 0.001));
  });

  test('a buyer with a saved address but no map pin still counts; the '
      'area has no coordinates until it is looked up by name', () {
    final sambat = demand.firstWhere((d) => d.area == 'Sambat, Tanauan');
    expect(sambat.orderCount, 2);
    expect(sambat.lat, isNull);
    expect(sambat.lng, isNull);

    final located = DashboardAnalyticsService.demandByBuyerAreaForMonth(
      orders,
      users,
      year: 2026,
      month: 10,
      areaCoordinates: {
        'Sambat, Tanauan': (lat: 14.08, lng: 121.13),
        // An area that already has buyers' locations keeps its own.
        'Bugaan East, Laurel': (lat: 0, lng: 0),
      },
    );
    final found = located.firstWhere((d) => d.area == 'Sambat, Tanauan');
    expect(found.lat, 14.08);
    expect(found.lng, 121.13);
    expect(located.first.area, 'Bugaan East, Laurel');
    expect(located.first.lat, isNot(0));
  });

  test('a purchase whose buyer has no saved location is counted as '
      'unmapped rather than dropped silently', () {
    final total = DashboardAnalyticsService.completedOrderCountForMonth(
      orders,
      year: 2026,
      month: 10,
    );
    final mapped = demand.fold<int>(0, (n, d) => n + d.orderCount);
    expect(total, 8);
    expect(mapped, 7);
  });

  group('area from an order\'s own address', () {
    test('keeps barangay and city, drops finer detail', () {
      expect(
        areaFromOrderAddress('Ihubok I, Basco, Batanes'),
        'Ihubok I, Basco',
      );
      expect(
        areaFromOrderAddress('Purok 2, Poblacion, Batangas City'),
        'Poblacion, Batangas City',
      );
      expect(
        areaFromOrderAddress('Purok 5, Tanauan, Batangas'),
        'Tanauan, Batangas',
      );
      expect(areaFromOrderAddress('Talisay, Batangas'), 'Talisay, Batangas');
      expect(
        areaFromOrderAddress(
          '123 Rizal St., Blk 4 Lot 2, Sambat, Tanauan, Batangas',
        ),
        'Sambat, Tanauan',
      );
    });

    test('free text is not guessed at, except a Laurel barangay by name', () {
      expect(areaFromOrderAddress('csegege'), isNull);
      expect(areaFromOrderAddress('ssan gabriel'), isNull);
      expect(areaFromOrderAddress(''), isNull);
      expect(areaFromOrderAddress(null), isNull);
      expect(areaFromOrderAddress('san gabriel'), 'San Gabriel, Laurel');
    });

    test('used only for a registered buyer with no saved location; an '
        'order with no buyer account behind it is not counted', () {
      OrderDoc addressed(String buyerId, String address) =>
          OrderDoc('a${_nextId++}', {
            'status': 'completed',
            'buyerId': buyerId,
            'buyerAddress': address,
            'total': 50,
            'completedAt': Timestamp.fromDate(DateTime(2026, 10, 3)),
          });
      final result = DashboardAnalyticsService.demandByBuyerAreaForMonth(
        [
          // A real account ('eve') that never saved a location: the
          // order's own address says where the purchase went.
          addressed('eve', 'Talisay, Batangas'),
          addressed('eve', 'Talisay, Batangas'),
          addressed('eve', 'csegege'),
          // Sample records written into orders by a script: the buyer id
          // is not an account, so they are not buyer demand.
          addressed('seed_buyer_01', 'Purok 2, Poblacion, Batangas City'),
          addressed('test_buyer_demo', 'Talisay, Batangas'),
          // A saved location wins over the address typed on the order.
          addressed('cora', 'Somewhere Else, Far Away'),
        ],
        users,
        year: 2026,
        month: 10,
      );
      expect(result.map((d) => (d.area, d.orderCount)), [
        ('Talisay, Batangas', 2),
        ('Leviste, Laurel', 1),
      ]);
      // Located by name later — the order carries no coordinate.
      expect(result.first.lat, isNull);
    });
  });
}
