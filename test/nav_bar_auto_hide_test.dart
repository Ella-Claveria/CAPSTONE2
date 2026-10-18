// The bottom bar slides away while a long page is scrolled down, and comes
// back on any scroll up; a short page keeps it.
import 'package:agritrade/widgets/docked_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Shell extends StatefulWidget {
  final int rows;
  const _Shell({required this.rows});
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: NavBarAutoHide(
      onHiddenChanged: (h) => setState(() => hidden = h),
      child: ListView(
        children: [
          for (var i = 0; i < widget.rows; i++)
            SizedBox(height: 60, child: Text('Row $i')),
        ],
      ),
    ),
    bottomNavigationBar: DockedNavBar(
      hidden: hidden,
      children: const [Expanded(child: Icon(Icons.explore))],
    ),
  );
}

void main() {
  double barHeight(WidgetTester tester) =>
      tester.getSize(find.byType(DockedNavBar)).height;

  testWidgets('scrolling down hides it, scrolling up brings it back', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell(rows: 40)));
    expect(barHeight(tester), greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(barHeight(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(barHeight(tester), greaterThan(0));
  });

  testWidgets('a short page keeps it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Shell(rows: 8)));
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(barHeight(tester), greaterThan(0));
  });
}
