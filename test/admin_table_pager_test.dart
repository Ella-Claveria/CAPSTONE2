// The Admin Portal's tables: 10 rows a page, a pager under them, and back
// to the first page when the search or a filter changes.
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('rows are split ten to a page', () {
    final rows = List.generate(34, (i) => i);
    expect(adminPageCount(34), 4);
    expect(adminPageCount(10), 1);
    expect(adminPageCount(0), 1);
    expect(adminPageOf(rows, 0), List.generate(10, (i) => i));
    expect(adminPageOf(rows, 3), [30, 31, 32, 33]);
    // A page past the end shows the last one.
    expect(adminPageOf(rows, 9), [30, 31, 32, 33]);
  });

  Widget host(List<int> items, Object filter) => MaterialApp(
    home: AdminThemeScope(
      palette: AdminPalette.light,
      child: Scaffold(
        body: SingleChildScrollView(
          child: AdminPaged<int>(
            items: items,
            resetKey: filter,
            builder: (context, page) =>
                Column(children: [for (final i in page) Text('row $i')]),
          ),
        ),
      ),
    ),
  );

  testWidgets('the pager moves between pages and starts again on a new '
      'filter', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = List.generate(23, (i) => i);
    await tester.pumpWidget(host(items, 'all'));
    expect(find.text('row 0'), findsOneWidget);
    expect(find.text('row 9'), findsOneWidget);
    expect(find.text('row 10'), findsNothing);
    expect(find.text('Showing 1–10 of 23'), findsOneWidget);
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOneWidget);
    }

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('row 20'), findsOneWidget);
    expect(find.text('row 0'), findsNothing);
    expect(find.text('Showing 21–23 of 23'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('row 10'), findsOneWidget);

    // A new filter: back to the first page.
    await tester.pumpWidget(host(items, 'farmers'));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);
  });

  testWidgets('one page needs no pager', (tester) async {
    await tester.pumpWidget(host(List.generate(7, (i) => i), 'all'));
    expect(find.text('row 6'), findsOneWidget);
    expect(find.byType(AdminTablePager), findsNothing);
  });
}
