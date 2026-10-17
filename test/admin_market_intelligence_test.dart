// The Admin Dashboard's Market Intelligence cards: the commodity search on
// Price Trend vs. Baseline, and Top-Selling Products — real figures only,
// with an empty state where there are no completed sales.
import 'package:agritrade/screen/admin_analytics_widgets.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    ),
  );
}

const commodities = ['Corn', 'Chicken', 'Coconut', 'Sweet Potato', 'Rice'];

Widget trendCard() => const AdminPriceTrendCard(
  commodities: commodities,
  baselineByCommodity: {'Chicken': 190, 'Rice': 52},
  weeklyPricesByCommodity: {
    'Chicken': [null, 210, null, null, null, null, null, 205],
    'Corn': [null, null, null, null, null, null, null, null],
    'Rice': [null, null, null, null, null, null, null, null],
  },
);

void main() {
  test('commodity search suggests names by the letters typed', () {
    expect(matchCommodities(commodities, 'ch'), ['Chicken']);
    expect(matchCommodities(commodities, 'co'), ['Coconut', 'Corn']);
    expect(matchCommodities(commodities, 'CO'), ['Coconut', 'Corn']);
    // A later word counts too, after names that start with the letters.
    expect(matchCommodities(commodities, 'po'), ['Sweet Potato']);
    expect(matchCommodities(['Sweet Corn', 'Corn'], 'co'), [
      'Corn',
      'Sweet Corn',
    ]);
    expect(matchCommodities(commodities, 'zz'), isEmpty);
    expect(matchCommodities(commodities, ''), [
      'Chicken',
      'Coconut',
      'Corn',
      'Rice',
      'Sweet Potato',
    ]);
  });

  testWidgets('Price Trend opens on a commodity with sales and has no chips', (
    tester,
  ) async {
    await pump(tester, trendCard());
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
    // Chicken is the only one with completed sales.
    expect(find.text('₱205.00/kg liveweight'), findsOneWidget);
    expect(find.text('₱190.00/kg liveweight'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Chicken',
    );
  });

  testWidgets('typing suggests matches; choosing one loads that commodity, '
      'with an empty state and its baseline when it has no sales', (
    tester,
  ) async {
    await pump(tester, trendCard());
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'co');
    await tester.pumpAndSettle();
    expect(find.text('Coconut'), findsOneWidget);
    expect(find.text('Corn'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ri');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsNothing);
    expect(
      find.text('No completed sales data available yet for this commodity.'),
      findsOneWidget,
    );
    // The Admin baseline still shows.
    expect(find.text('₱52.00/kg'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Rice',
    );

    // A commodity with neither sales nor a baseline says so.
    await tester.enterText(find.byType(TextField), 'coc');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coconut'));
    await tester.pumpAndSettle();
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('Top-Selling Products lists rank, quantity and sales value', (
    tester,
  ) async {
    await pump(
      tester,
      const AdminTopProductsCard(
        products: [
          (name: 'Red Onion', revenue: 2400, quantity: 25),
          (name: 'Yellow Corn', revenue: 2180, quantity: 75),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Red Onion'), findsOneWidget);
    expect(find.text('₱2,400.00'), findsOneWidget);
    expect(find.text('25 kg sold'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Red Onion')).dy,
      lessThan(tester.getTopLeft(find.text('Yellow Corn')).dy),
    );
  });

  testWidgets('both cards are the same height, and Top-Selling Products '
      'has an empty state', (tester) async {
    await pump(
      tester,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: trendCard()),
          const SizedBox(width: 16),
          const Expanded(flex: 2, child: AdminTopProductsCard(products: [])),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('No completed sales data available yet.'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AdminTopProductsCard)).height,
      tester.getSize(find.byType(AdminPriceTrendCard)).height,
    );
  });
}
