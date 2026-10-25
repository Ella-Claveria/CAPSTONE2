import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_price_trend_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(int year, int month, num price) => {
  'productName': 'Tomato',
  'unit': 'kg',
  'pricingType': 'retail',
  'pricePerUnit': price,
  'completedAt': Timestamp.fromDate(DateTime(year, month, 10)),
};

Future<void> _show(WidgetTester tester, List<Map<String, dynamic>> orders) =>
    tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Scaffold(
            body: SingleChildScrollView(
              child: AdminPriceTrendChart(
                commodity: 'Tomato',
                products: const [],
                completedOrders: orders,
                historical: const [],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  testWidgets('two lines, the previous year against the current one', (
    tester,
  ) async {
    final year = DateTime.now().year;
    await _show(tester, [
      _sale(year - 1, 2, 50),
      _sale(year - 1, 6, 55),
      _sale(year, 2, 60),
      // A gap in March–May, then June.
      _sale(year, 6, 75),
    ]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('${year - 1} vs $year'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    // (50 + 55) / 2 = 52.50 against (60 + 75) / 2 = 67.50.
    expect(find.textContaining('up 28.6%'), findsOneWidget);
  });

  testWidgets('no prices in either year: says so instead of a chart', (
    tester,
  ) async {
    await _show(tester, const []);
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('No Tomato prices on record'), findsOneWidget);
  });
}
