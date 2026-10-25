import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/market_demand_index.dart';
import 'package:agritrade/widgets/demand_badge.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(String product) => {
  'productName': product,
  'status': 'completed',
  'unit': 'kg',
  'buyerArea': 'Laurel',
  // This month, so it is on the current Best-Selling list.
  'completedAt': Timestamp.fromDate(
    DateTime(DateTime.now().year, DateTime.now().month),
  ),
};

Future<void> _show(WidgetTester tester, String productName) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DemandBadge(productName: productName)),
      ),
    );

void main() {
  setUp(() {
    CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
    ]);
    MarketDemandIndex.instance.debugSetSales([
      for (var i = 0; i < 6; i++) _sale('Tomato'), // the top seller: High
      for (var i = 0; i < 3; i++) _sale('Eggplant'), // a third or more
      _sale('Banana'), // under a third: Low
    ]);
  });
  tearDown(() {
    MarketDemandIndex.instance.debugSetSales(const []);
    CommodityRegistry.instance.applyAdminRecords(const []);
  });

  testWidgets('a top seller shows High demand with its trend arrow', (
    tester,
  ) async {
    // A listing name is matched to its commodity, as on the farmer's card.
    await _show(tester, 'Fresh Native Tomato');
    expect(find.text('High demand'), findsOneWidget);
    // Nothing sold last month: rising.
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
  });

  testWidgets('a moderate seller shows Moderate demand', (tester) async {
    await _show(tester, 'Eggplant');
    expect(find.text('Moderate demand'), findsOneWidget);
  });

  testWidgets('low demand, or not a best seller, shows nothing', (
    tester,
  ) async {
    await _show(tester, 'Banana');
    expect(find.textContaining('demand'), findsNothing);
    await _show(tester, 'Squash');
    expect(find.textContaining('demand'), findsNothing);
  });
}
