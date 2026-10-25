// The Admin Analytics Dashboard's Overview strip and Sales Performance
// charts: real figures only, completed orders only, and an empty state —
// never a chart of zeros — when the period has no sales.
import 'package:agritrade/data/report_reasons.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_overview_widgets.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> order(String status, DateTime completedAt, num total) => {
  'status': status,
  // Orders carry Firestore timestamps.
  'completedAt': Timestamp.fromDate(completedAt),
  'total': total,
};

Future<void> pump(WidgetTester tester, Widget child, {double width = 1400}) {
  tester.view.physicalSize = Size(width, 900);
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

void main() {
  final now = DateTime(2026, 10, 10);

  group('monthlyCompletedSales', () {
    test('groups completed orders by month, oldest first', () {
      final sales = DashboardAnalyticsService.monthlyCompletedSales([
        order('completed', DateTime(2026, 10, 2), 100),
        order('completed', DateTime(2026, 10, 9), 50.5),
        order('Completed', DateTime(2026, 8, 20), 300),
        order('completed', DateTime(2026, 5, 1), 40),
      ], now: now);
      expect(sales.length, 6);
      expect(sales.first.month, DateTime(2026, 5, 1));
      expect(sales.last.month, DateTime(2026, 10, 1));
      expect(sales.map((m) => m.revenue), [40, 0, 0, 300, 0, 150.5]);
      expect(sales.map((m) => m.orders), [1, 0, 0, 1, 0, 2]);
    });

    test('ignores orders that are not completed or outside the period', () {
      final sales = DashboardAnalyticsService.monthlyCompletedSales([
        order('pending', DateTime(2026, 10, 2), 100),
        order('cancelled', DateTime(2026, 9, 2), 100),
        order('rejected', DateTime(2026, 9, 3), 100),
        order('completed', DateTime(2026, 4, 30), 999),
        order('completed', DateTime(2025, 10, 5), 999),
      ], now: now);
      expect(sales.every((m) => m.revenue == 0 && m.orders == 0), isTrue);
    });

    test('a period can cross into the previous year', () {
      final sales = DashboardAnalyticsService.monthlyCompletedSales(
        [order('completed', DateTime(2025, 12, 31), 70)],
        now: DateTime(2026, 2, 14),
        months: 3,
      );
      expect(sales.map((m) => m.month), [
        DateTime(2025, 12, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 1),
      ]);
      expect(sales.first.revenue, 70);
    });

    test('lastMonthsRange starts on the 1st of the earliest month', () {
      final range = DashboardAnalyticsService.lastMonthsRange(now, 6);
      expect(range.start, DateTime(2026, 5, 1));
      expect(range.end, now);
    });
  });

  test('report reasons differ by who is reporting', () {
    expect(reportReasonsFor('buyer'), contains('Price Gouging'));
    expect(reportReasonsFor('buyer'), isNot(contains('Bogus Buyer')));
    expect(reportReasonsFor('farmer'), contains('Bogus Buyer'));
    expect(reportReasonsFor('farmer'), isNot(contains('Price Gouging')));
    expect(reportReasonsFor('buyer').length, 7);
    expect(reportReasonsFor('farmer').length, 7);
    expect(reportTargetTypeFor('buyer'), 'farmer');
    expect(reportTargetTypeFor('farmer'), 'buyer');
  });

  const items = [
    AdminOverviewItem(
      label: 'Total Users',
      icon: Icons.groups_2_outlined,
      value: '11',
      caption: '6 approved farmers · 5 buyers',
    ),
    AdminOverviewItem(
      label: 'Pending Verifications',
      icon: Icons.fact_check_outlined,
      value: null,
      caption: '',
    ),
    AdminOverviewItem(
      label: 'Flagged Reports',
      icon: Icons.flag_outlined,
      value: '—',
      caption: 'Could not load · try Refresh',
      failed: true,
    ),
    AdminOverviewItem(
      label: 'Total Transaction Value',
      icon: Icons.payments_outlined,
      value: '₱16,456.00',
      caption: 'Completed orders only',
    ),
  ];

  testWidgets('the Overview is one row of four equal segments', (tester) async {
    await pump(tester, const AdminOverviewStrip(items: items));
    expect(tester.takeException(), isNull);
    final rects = [
      for (final item in items) tester.getRect(find.text(item.label)),
    ];
    // One row, left to right, evenly spaced.
    expect(rects.map((r) => r.top).toSet().length, 1);
    final step = rects[1].left - rects[0].left;
    expect(rects[2].left - rects[1].left, closeTo(step, 0.5));
    expect(rects[3].left - rects[2].left, closeTo(step, 0.5));
    expect(find.text('11'), findsOneWidget);
    expect(find.text('₱16,456.00'), findsOneWidget);
    // Compact: well under the height of the old cards.
    expect(
      tester.getSize(find.byType(AdminOverviewStrip)).height,
      lessThan(100),
    );
  });

  testWidgets('the Overview wraps on a narrow window without overflowing', (
    tester,
  ) async {
    await pump(tester, const AdminOverviewStrip(items: items), width: 700);
    expect(tester.takeException(), isNull);
    final a = tester.getRect(find.text('Total Users'));
    final c = tester.getRect(find.text('Flagged Reports'));
    expect(c.top, greaterThan(a.top));
    expect(c.left, a.left);

    await pump(tester, const AdminOverviewStrip(items: items), width: 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sales Performance says so when the product has no completed '
      'orders in the period', (tester) async {
    await pump(
      tester,
      AdminSalesPerformanceCard(
        orders: [
          {...order('pending', DateTime.now(), 500), 'productName': 'Corn'},
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('No completed orders of'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Last 6 Months'), findsOneWidget);
    expect(find.text('All Categories'), findsOneWidget);
  });

  testWidgets('Sales Performance shows one product\'s demand month by '
      'month, opening on the best seller, and its period filter changes '
      'the months shown', (tester) async {
    final today = DateTime.now();
    final lastMonth = DateTime(today.year, today.month - 1, 10);
    Map<String, dynamic> sale(
      String product,
      DateTime at,
      num quantity,
      num total,
    ) => {
      ...order('completed', at, total),
      'productName': product,
      'quantity': quantity,
      'unit': 'kg',
    };
    await pump(
      tester,
      AdminSalesPerformanceCard(
        orders: [
          sale('Corn', lastMonth, 30, 900),
          sale('Corn', today, 10, 300),
          sale('Corn', today, 5, 150),
          sale('Cassava', today, 4, 100),
          {...order('cancelled', today, 9999), 'productName': 'Corn'},
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    // Corn sold the most, so it is shown first.
    expect(find.text('Corn'), findsOneWidget);
    expect(find.text('45 kg sold'), findsOneWidget);
    expect(
      find.textContaining('₱1,350.00 · 3 completed orders'),
      findsOneWidget,
    );
    expect(find.textContaining('Best month: '), findsOneWidget);
    List<FlSpot> points() => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single
        .spots;
    expect(points().length, 6);
    // 30 kg last month, down to 15 kg this month.
    expect(points()[4].y, 30);
    expect(points().last.y, 15);

    await tester.tap(find.text('Last 6 Months'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 12 Months').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(points().length, 12);

    // A category narrows the products; it opens on its own best seller.
    await tester.tap(find.text('All Categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Root Crops').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cassava'), findsOneWidget);
    expect(find.text('4 kg sold'), findsOneWidget);
  });

  testWidgets('Sales by Category lists real categories and their shares, '
      'and matches the Sales Performance card in height', (tester) async {
    await pump(
      tester,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: AdminSalesPerformanceCard(
              orders: [order('completed', DateTime.now(), 100)],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: AdminSalesByCategoryCard(
              revenueFor: (months) => months == 6
                  ? {'Vegetables': 750, 'Fruits': 250, 'Grains': 0}
                  : {},
            ),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Vegetables'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    // A category with no sales is not listed.
    expect(find.text('Grains'), findsNothing);
    expect(find.text('₱1,000.00'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AdminSalesByCategoryCard)).height,
      tester.getSize(find.byType(AdminSalesPerformanceCard)).height,
    );

    await tester.tap(find.text('Last 6 Months').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 3 Months').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No completed category sales data available for the selected period.',
      ),
      findsOneWidget,
    );
    expect(find.byType(PieChart), findsNothing);
  });
}
