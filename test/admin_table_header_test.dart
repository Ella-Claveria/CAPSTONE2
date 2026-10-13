import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a table keeps its header in view while the page scrolls', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 120),
                AdminTableFit(
                  table: DataTable(
                    columns: const [DataColumn(label: Text('Commodity'))],
                    rows: [
                      for (var i = 0; i < 60; i++)
                        DataRow(cells: [DataCell(Text('Row $i'))]),
                    ],
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Not scrolled: only the table's own header, and the table is as wide
    // as the page it is in.
    expect(find.text('Commodity'), findsOneWidget);
    expect(tester.getSize(find.byType(DataTable)).width, 800);

    // Scrolled into the rows: the header is held at the top of the page.
    scroll.jumpTo(700);
    await tester.pump();
    await tester.pump();
    expect(find.text('Commodity'), findsNWidgets(2));
    for (final table in find.byType(DataTable).evaluate()) {
      expect(table.size!.width, 800);
    }
    final held = tester.getTopLeft(find.text('Commodity').last).dy;
    expect(held, greaterThanOrEqualTo(0));
    expect(held, lessThan(56));

    // Scrolled past the table: the held header went with its last row.
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    for (final header in find.text('Commodity').evaluate()) {
      final box = header.renderObject! as RenderBox;
      expect(box.localToGlobal(Offset.zero).dy, lessThan(0));
    }

    // Back at the top: the copy is gone again.
    scroll.jumpTo(0);
    await tester.pump();
    expect(find.text('Commodity'), findsOneWidget);
  });
}
