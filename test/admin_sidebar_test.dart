// The Admin Portal's left sidebar: the pages in order, the active one
// highlighted, every page an item of its own, and the icon-only rail.
import 'package:agritrade/widgets/admin_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const entries = [
  AdminSidebarEntry(Icons.dashboard_outlined, 'Dashboard'),
  AdminSidebarEntry(Icons.map_outlined, 'Demand Heatmap'),
  AdminSidebarEntry(Icons.insights_outlined, 'Market Forecasts'),
  AdminSidebarEntry(Icons.verified_user_outlined, 'Verification'),
  AdminSidebarEntry(Icons.groups_outlined, 'Farmers'),
  AdminSidebarEntry(Icons.gavel_outlined, 'Moderation'),
  AdminSidebarEntry(Icons.price_change_outlined, 'Price Management'),
  AdminSidebarEntry(Icons.fact_check_outlined, 'Audit Log'),
];

class Host extends StatefulWidget {
  final bool collapsed;
  const Host({super.key, this.collapsed = false});

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AdminSidebar(
            entries: entries,
            selectedIndex: selected,
            collapsed: widget.collapsed,
            onSelect: (i) => setState(() => selected = i),
          ),
          Expanded(child: Text('page $selected')),
        ],
      ),
    );
  }
}

Future<HostState> pump(
  WidgetTester tester, {
  bool collapsed = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Host(collapsed: collapsed)));
  return tester.state<HostState>(find.byType(Host));
}

/// The background colour of the row showing [label].
Color? rowColor(WidgetTester tester, String label) {
  final box = tester.widget<AnimatedContainer>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('lists every page in order, Audit Log last', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    const order = [
      'Dashboard',
      'Demand Heatmap',
      'Market Forecasts',
      'Verification',
      'Farmers',
      'Moderation',
      'Price Management',
      'Audit Log',
    ];
    var lastY = -1.0;
    for (final label in order) {
      final y = tester.getTopLeft(find.text(label)).dy;
      expect(y, greaterThan(lastY), reason: label);
      lastY = y;
    }
    // No extra navigation level.
    expect(find.text('More'), findsNothing);
    expect(find.text('AgriTrade+'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AdminSidebar)).width,
      inInclusiveRange(240, 260),
    );
  });

  testWidgets('the active page is highlighted and follows the selection', (
    tester,
  ) async {
    final host = await pump(tester);
    expect(rowColor(tester, 'Dashboard'), AdminSidebar.activeBackground);
    expect(rowColor(tester, 'Farmers')!.a, 0);

    await tester.tap(find.text('Farmers'));
    await tester.pumpAndSettle();
    expect(host.selected, 4);
    expect(find.text('page 4'), findsOneWidget);
    expect(rowColor(tester, 'Farmers'), AdminSidebar.activeBackground);
    expect(rowColor(tester, 'Dashboard')!.a, 0);
  });

  testWidgets('the active tab is cream, flush with the left edge and '
      'rounded on the right only', (tester) async {
    await pump(tester);
    final row = find
        .ancestor(
          of: find.text('Dashboard'),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    expect(
      tester.getTopLeft(row).dx,
      tester.getTopLeft(find.byType(AdminSidebar)).dx,
    );
    final decoration =
        tester.widget<AnimatedContainer>(row).decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFF2F3E9));
    expect(decoration.border, isNull);
    expect(decoration.boxShadow, isNull);
    final radius = decoration.borderRadius as BorderRadius;
    expect(radius.topLeft, Radius.zero);
    expect(radius.bottomLeft, Radius.zero);
    expect(radius.topRight.x, inInclusiveRange(16, 20));
    expect(radius.bottomRight.x, inInclusiveRange(16, 20));
    // Dark green icon and text on it.
    expect(
      tester.widget<Text>(find.text('Dashboard')).style!.color,
      AdminSidebar.background,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.dashboard_outlined)).color,
      AdminSidebar.background,
    );
    // Same width as before.
    expect(tester.getSize(find.byType(AdminSidebar)).width, 248);
  });

  testWidgets('Audit Log is a row of its own and is highlighted when open', (
    tester,
  ) async {
    final host = await pump(tester);
    await tester.tap(find.text('Audit Log'));
    await tester.pumpAndSettle();
    expect(host.selected, 7);
    expect(rowColor(tester, 'Audit Log'), AdminSidebar.activeBackground);
    expect(rowColor(tester, 'Dashboard')!.a, 0);
  });

  testWidgets('the rail shows icons only, with every page still reachable', (
    tester,
  ) async {
    final host = await pump(
      tester,
      collapsed: true,
      size: const Size(900, 700),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AdminSidebar)).width, 72);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('AgriTrade+'), findsNothing);
    for (final entry in entries) {
      expect(find.byIcon(entry.icon), findsOneWidget);
      expect(find.byTooltip(entry.label), findsOneWidget);
    }
    await tester.tap(find.byIcon(Icons.gavel_outlined));
    await tester.pumpAndSettle();
    expect(host.selected, 5);

    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pumpAndSettle();
    expect(host.selected, 7);
  });

  testWidgets('scrolls on its own when the window is too short', (
    tester,
  ) async {
    await pump(tester, size: const Size(1440, 320));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Audit Log'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
