import 'package:agritrade/widgets/market_card_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, int count) => tester.pumpWidget(
  MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: SingleChildScrollView(
          child: marketCardRows(
            rows: [for (var i = 1; i <= count; i++) Text('Row $i')],
            showAll: false,
            openAll: () => openMarketCardScreen(
              context,
              title: 'Best-Selling Products',
              child: marketCardRows(
                rows: [for (var i = 1; i <= count; i++) Text('Row $i')],
                showAll: true,
                openAll: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('five rows or fewer: all on the card, no View all', (
    tester,
  ) async {
    await _show(tester, 5);
    expect(find.text('Row 5'), findsOneWidget);
    expect(find.textContaining('View All'), findsNothing);
  });

  testWidgets('more than five: the first five, then View all opens every '
      'row on its own screen', (tester) async {
    await _show(tester, 8);
    expect(find.text('Row 5'), findsOneWidget);
    expect(find.text('Row 6'), findsNothing);

    await tester.tap(find.text('View All (8)'));
    await tester.pumpAndSettle();

    expect(find.text('Best-Selling Products'), findsOneWidget);
    for (var i = 1; i <= 8; i++) {
      expect(find.text('Row $i'), findsOneWidget);
    }
    expect(find.textContaining('View All'), findsNothing);
  });
}
