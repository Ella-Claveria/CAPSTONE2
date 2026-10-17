// The Demand Heatmap's colour scale and legend, Highest Demand Areas, and
// Most Purchased Products by Area — completed buyer purchases only.
// ignore_for_file: subtype_of_sealed_class
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_demand_widgets.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

OrderDoc order(
  String buyerId,
  String product,
  num quantity, {
  String status = 'completed',
  int month = 10,
  String? unit,
}) => OrderDoc('o${_nextId++}', {
  'status': status,
  'buyerId': buyerId,
  'productName': product,
  'quantity': quantity,
  'unit': ?unit,
  'completedAt': Timestamp.fromDate(DateTime(2026, month, 5)),
});

Future<void> pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(520, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

void main() {
  final users = <String, Map<String, dynamic>>{
    'ana': {'barangay': 'San Gregorio', 'municipality': 'Laurel'},
    'ben': {'barangay': 'San Gregorio', 'municipality': 'Laurel'},
    'cora': {'barangay': 'Sambat', 'municipality': 'Tanauan'},
  };

  group('most purchased products by area', () {
    final products = DashboardAnalyticsService.productsByBuyerAreaForMonth(
      [
        order('ana', 'Eggplant', 100, unit: 'kg'),
        order('ben', 'Fresh Native Eggplant', 80, unit: 'kg'),
        order('ana', 'Rice', 250, unit: 'kg'),
        order('ben', 'Tomato', 20, unit: 'kg'),
        order('cora', 'Tomato', 5, unit: 'kg'),
        // None of these count.
        order('ana', 'Tomato', 9999, unit: 'kg', status: 'pending'),
        order('ana', 'Tomato', 9999, unit: 'kg', status: 'cancelled'),
        order('ana', 'Tomato', 9999, unit: 'kg', status: 'rejected'),
        order('ana', 'Tomato', 9999, unit: 'kg', month: 9),
        order('nobody', 'Tomato', 9999, unit: 'kg'),
      ],
      users,
      year: 2026,
      month: 10,
    );

    test('grouped by buyer area, completed orders of the month only', () {
      expect(products.keys.toSet(), {
        'San Gregorio, Laurel',
        'Sambat, Tanauan',
      });
      expect(products['Sambat, Tanauan']!.single.quantity, 5);
    });

    test('ranked by total quantity, with orders, category and unit', () {
      final area = products['San Gregorio, Laurel']!;
      expect(area.map((p) => p.product), ['Rice', 'Eggplant', 'Tomato']);
      // Two listings of the same commodity are one product.
      expect(area[1].quantity, 180);
      expect(area[1].orders, 2);
      expect(area[1].unit, 'kg');
      expect(area[1].category, isNotEmpty);
      expect(area[2].quantity, 20);
      expect(area[2].orders, 1);
    });
  });

  group('heat scale', () {
    test('green for low, yellow/orange for medium, red for high', () {
      expect(heatColorForIntensity(0), kHeatLow);
      expect(heatColorForIntensity(1), kHeatHigh);
      expect(heatLevelLabel(0.2), 'Low Demand');
      expect(heatLevelLabel(0.5), 'Medium Demand');
      expect(heatLevelLabel(0.9), 'High Demand');
      final medium = heatColorForIntensity(0.5);
      expect(medium, isNot(kHeatLow));
      expect(medium, isNot(kHeatHigh));
    });

    test('intensity follows the number of completed purchases', () {
      expect(demandIntensity(40, 40), 1);
      expect(demandIntensity(20, 40), 0.5);
      expect(demandIntensity(4, 40), 0.1);
      // With very little data, one purchase is not "the highest demand".
      expect(demandIntensity(1, 1), 1 / kHeatScaleFloor);
      expect(heatLevelLabel(demandIntensity(1, 1)), 'Low Demand');
    });
  });

  testWidgets('the legend names all three levels', (tester) async {
    await pump(tester, const Align(child: AdminHeatLegend()));
    expect(tester.takeException(), isNull);
    expect(find.text('Green = Low Demand'), findsOneWidget);
    expect(find.text('Yellow/Orange = Medium Demand'), findsOneWidget);
    expect(find.text('Red = High Demand'), findsOneWidget);
  });

  testWidgets('choosing an area in Highest Demand Areas shows that area\'s '
      'products; the two panels are the same height', (tester) async {
    const areas = [
      (area: 'San Gregorio, Laurel', orderCount: 12),
      (area: 'Sambat, Tanauan', orderCount: 3),
    ];
    const products = {
      'San Gregorio, Laurel': [
        (
          product: 'Chicken',
          category: 'Livestock',
          quantity: 120.0,
          unit: 'head',
          orders: 45,
        ),
        (
          product: 'Eggplant',
          category: 'Vegetables',
          quantity: 180.0,
          unit: 'kg',
          orders: 32,
        ),
      ],
      'Sambat, Tanauan': [
        (
          product: 'Rice',
          category: 'Grains',
          quantity: 250.0,
          unit: 'kg',
          orders: 20,
        ),
      ],
    };
    String selected = areas.first.area;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            Expanded(
              child: AdminDemandAreasPanel(
                areas: areas,
                selectedArea: selected,
                onSelect: (area) => setState(() => selected = area),
                emptyText: 'none',
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AdminAreaProductsPanel(
                area: selected,
                products: products[selected]!,
                emptyText: 'none',
              ),
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Rank, name and count.
    expect(find.text('12 purchases'), findsOneWidget);
    expect(find.text('3 purchases'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Livestock'), findsOneWidget);
    expect(find.text('45 orders / 120 heads'), findsOneWidget);
    expect(find.text('32 orders / 180 kg'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);
    expect(
      tester.getSize(find.byType(AdminDemandAreasPanel)).height,
      tester.getSize(find.byType(AdminAreaProductsPanel)).height,
    );

    await tester.tap(find.text('Sambat, Tanauan'));
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('20 orders / 250 kg'), findsOneWidget);
    expect(find.text('Chicken'), findsNothing);
  });

  testWidgets('with no completed purchases both panels say so', (tester) async {
    const message = 'No completed buyer purchases for this period.';
    await pump(
      tester,
      Column(
        children: [
          Expanded(
            child: AdminDemandAreasPanel(
              areas: const [],
              selectedArea: null,
              onSelect: (_) {},
              emptyText: message,
            ),
          ),
          const Expanded(
            child: AdminAreaProductsPanel(
              area: null,
              products: [],
              emptyText: message,
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(message), findsNWidgets(2));
  });
}
