// The Admin sidebar's collapsible submenus: a chevron on pages that have
// several views, the views listed under it, and the open one highlighted.
import 'package:agritrade/screen/admin_sub_nav.dart';
import 'package:agritrade/services/audit_log_service.dart';
import 'package:agritrade/widgets/admin_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const entries = [
  AdminSidebarEntry(Icons.dashboard_outlined, 'Dashboard'),
  AdminSidebarEntry(
    Icons.gavel_outlined,
    'Moderation',
    children: ['Pending Reports', 'Under Review', 'Resolved Reports'],
  ),
  AdminSidebarEntry(Icons.price_change_outlined, 'Price Management'),
  AdminSidebarEntry(
    Icons.fact_check_outlined,
    'Audit Log',
    children: ['All Activity', 'Login Activity'],
  ),
];

class Host extends StatefulWidget {
  final bool collapsed;
  const Host({super.key, this.collapsed = false});

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  int selected = 0;
  final children = <int, int>{1: 0, 3: 0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AdminSidebar(
            entries: entries,
            selectedIndex: selected,
            selectedChildIndex: children[selected],
            collapsed: widget.collapsed,
            onSelect: (i) => setState(() => selected = i),
            onSelectChild: (i, child) => setState(() {
              selected = i;
              children[i] = child;
            }),
          ),
          Expanded(child: Text('page $selected/${children[selected]}')),
        ],
      ),
    );
  }
}

Future<HostState> pump(WidgetTester tester, {bool collapsed = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Host(collapsed: collapsed)));
  return tester.state<HostState>(find.byType(Host));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('only pages with several views have a chevron, and their '
      'submenus start closed', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    expect(find.text('Pending Reports'), findsNothing);
    expect(find.text('All Activity'), findsNothing);
  });

  testWidgets('clicking a parent opens its page and its submenu; clicking '
      'it again folds the submenu', (tester) async {
    final host = await pump(tester);
    await tester.tap(find.text('Moderation'));
    await tester.pumpAndSettle();
    expect(host.selected, 1);
    expect(find.text('Pending Reports'), findsOneWidget);
    expect(find.text('Resolved Reports'), findsOneWidget);

    await tester.tap(find.text('Moderation'));
    await tester.pumpAndSettle();
    expect(host.selected, 1);
    expect(find.text('Pending Reports'), findsNothing);
  });

  testWidgets('the chevron folds a submenu without leaving the page', (
    tester,
  ) async {
    final host = await pump(tester);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded).last);
    await tester.pumpAndSettle();
    expect(host.selected, 0);
    expect(find.text('Login Activity'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Login Activity'), findsNothing);
  });

  testWidgets('a submenu item opens its view and is the highlighted one; '
      'it is smaller and indented under its parent', (tester) async {
    final host = await pump(tester);
    await tester.tap(find.text('Moderation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved Reports'));
    await tester.pumpAndSettle();
    expect(host.selected, 1);
    expect(find.text('page 1/2'), findsOneWidget);

    TextStyle style(String label) =>
        tester.widget<Text>(find.text(label)).style!;
    expect(style('Resolved Reports').fontWeight, FontWeight.w600);
    expect(style('Pending Reports').fontWeight, FontWeight.w500);
    expect(style('Resolved Reports').color!.a, 1);
    expect(style('Pending Reports').color!.a, lessThan(1));
    expect(
      style('Resolved Reports').fontSize!,
      lessThan(style('Moderation').fontSize!),
    );
    expect(
      tester.getTopLeft(find.text('Resolved Reports')).dx,
      greaterThan(tester.getTopLeft(find.text('Moderation')).dx),
    );
    // The sidebar keeps its width.
    expect(tester.getSize(find.byType(AdminSidebar)).width, 248);
  });

  testWidgets('the icon rail has no submenus or chevrons', (tester) async {
    final host = await pump(tester, collapsed: true);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.gavel_outlined));
    await tester.pumpAndSettle();
    expect(host.selected, 1);
    expect(find.text('Pending Reports'), findsNothing);
  });

  testWidgets('the footer (the Admin account) stays pinned at the bottom '
      'while the pages scroll', (tester) async {
    tester.view.physicalSize = const Size(1440, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AdminSidebar(
                entries: entries,
                selectedIndex: 0,
                onSelect: (_) {},
                footer: const SizedBox(height: 56, child: Text('account')),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final sidebar = tester.getRect(find.byType(AdminSidebar));
    double footerBottom() => tester.getRect(find.text('account')).top + 56;
    expect(footerBottom(), sidebar.bottom);

    // The window is too short for every page: scroll them. The footer
    // does not move.
    await tester.drag(find.text('Dashboard'), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(footerBottom(), sidebar.bottom);
    expect(find.byType(Divider), findsOneWidget);
  });

  test('every audit action belongs to exactly one Audit Log section', () {
    final grouped = [
      for (final section in AuditSection.values) ...?section.actions,
    ];
    expect(grouped.toSet().length, grouped.length);
    expect(grouped.toSet(), AuditAction.all.toSet());
    expect(AuditSection.all.actions, isNull);
  });
}
