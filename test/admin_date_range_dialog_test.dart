import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_date_range_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DateTimeRange? Function()> open(
    WidgetTester tester, {
    DateTimeRange? initial,
  }) async {
    DateTimeRange? result;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAdminDateRangePicker(
                context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2026, 10, 12),
                initialDateRange: initial,
                palette: AdminPalette.light,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('two days clicked and applied are the range', (tester) async {
    final result = await open(tester);
    expect(find.text('October 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('5'));
    await tester.tap(find.text('9'));
    await tester.pump();
    expect(find.text('Oct 5, 2026'), findsOneWidget);
    expect(find.text('Oct 9, 2026'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      result(),
      DateTimeRange(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 9)),
    );
  });

  testWidgets('one day applied is a range of that day; a day after the last '
      'date cannot be chosen', (tester) async {
    final result = await open(tester);
    // The 20th is after the last date.
    await tester.tap(find.text('20'));
    await tester.pump();
    expect(find.text('Oct 20, 2026'), findsNothing);

    await tester.tap(find.text('8'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      result(),
      DateTimeRange(start: DateTime(2026, 10, 8), end: DateTime(2026, 10, 8)),
    );
  });

  testWidgets('the single-date calendar returns the day clicked', (
    tester,
  ) async {
    DateTime? result;
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAdminDatePicker(
                context,
                initialDate: DateTime(2026, 10, 12),
                firstDate: DateTime(2000),
                lastDate: DateTime(2026, 10, 12),
                title: 'Price date',
                palette: AdminPalette.light,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Price date'), findsOneWidget);
    expect(find.text('Start date'), findsNothing);
    expect(find.text('Oct 12, 2026'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('Oct 3, 2026'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 10, 3));
  });

  testWidgets('a shortcut fills both dates; the arrows turn the month; '
      'Cancel returns nothing', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Last 7 days'));
    await tester.pump();
    expect(find.text('Oct 6, 2026'), findsOneWidget);
    expect(find.text('Oct 12, 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
