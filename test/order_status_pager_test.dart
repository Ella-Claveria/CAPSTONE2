// Minimal stand-ins for Firestore snapshots (only id / data / docs used).
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:agritrade/services/order_format.dart';
import 'package:agritrade/services/order_seen_service.dart';
import 'package:agritrade/widgets/order_status_pager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;

  /// [activity]: when the other party last changed this order (0 = never).
  _Doc(this.id, String status, {int activity = 0})
    : _data = {'status': status, 'activity': activity};

  @override
  Map<String, dynamic> data() => _data;
}

class _Snap extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  _Snap(this.docs);
}

const _tutorialKey = 'orders_swipe_tutorial_seen_test';
const _seenStore = OrderSeenStore(uid: 'u1', role: 'farmer');

Widget _app(
  Stream<QuerySnapshot<Map<String, dynamic>>> stream, {
  bool newUser = false,
  OrderSeenStore seenStore = _seenStore,
}) => MaterialApp(
  home: Scaffold(
    body: OrderStatusPager(
      streamFactory: () => stream,
      itemsBuilder: (tab, all, isNew) => [
        for (final d in all.where((d) => orderStatusOf(d) == tab.value))
          ListTile(title: Text('order ${d.id}${isNew(d) ? ' NEW' : ''}')),
      ],
      onRefresh: () async {},
      emptySubtitle: (tab) => '${tab.label} orders will appear here.',
      errorMessage: 'Could not load orders.',
      tutorialPrefsKey: _tutorialKey,
      tutorialEligible: () => newUser,
      activityOf: (doc) => doc.data()['activity'] as int,
      seenStore: seenStore,
    ),
  ),
);

Finder _badge(String label) => find.byKey(ValueKey('order-tab-badge-$label'));

/// Colour the tab label [label] is drawn in.
Color? _labelColor(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style?.color;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final orders = _Snap([
    _Doc('p1', 'pending'),
    _Doc('p2', 'pending'),
    _Doc('c1', 'confirmed'),
    for (var i = 0; i < 5; i++) _Doc('d$i', 'completed'),
  ]);

  testWidgets('first load shows only a thin bar, never skeleton cards', (
    tester,
  ) async {
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(controller.stream));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Tabs are already there.
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    controller.add(orders);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('order p1'), findsOneWidget);
  });

  testWidgets('tabs are plain text: no badge for already-seen orders', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Stream.value(orders)));
    await tester.pumpAndSettle();

    // Eight orders, none with unseen activity: no badge, and never a "0".
    for (final label in ['Pending', 'Confirmed', 'Shipped', 'Completed']) {
      expect(_badge(label), findsNothing);
    }
    expect(find.text('0'), findsNothing);
    expect(find.text('2'), findsNothing);
    // No filled pill behind the labels any more.
    expect(
      find.ancestor(
        of: find.text('Pending'),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
    );
  });

  testWidgets('badge counts only unseen activity and clears once seen', (
    tester,
  ) async {
    // This account has opened Orders before and has seen up to t=100.
    SharedPreferences.setMockInitialValues({
      'orders_seen_farmer_u1': '{"pending":100,"confirmed":100}',
    });
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(controller.stream));

    // Pending orders that were all already seen: no badge.
    final old = [
      for (var i = 0; i < 3; i++) _Doc('o$i', 'pending', activity: 50),
    ];
    controller.add(_Snap(old));
    await tester.pumpAndSettle();
    expect(_badge('Pending'), findsNothing);

    // Two new orders arrive, plus activity on another tab.
    controller.add(
      _Snap([
        ...old,
        _Doc('n1', 'pending', activity: 200),
        _Doc('n2', 'pending', activity: 300),
        _Doc('c1', 'confirmed', activity: 250),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: _badge('Pending'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _badge('Confirmed'), matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('order n1 NEW'), findsOneWidget);

    // On the upper-right corner of the label, not beside it.
    final label = tester.getRect(find.text('Pending'));
    final badge = tester.getRect(_badge('Pending'));
    expect(badge.center.dx, greaterThan(label.right));
    expect(badge.center.dy, lessThan(label.top + 4));

    // Pending is the open page: after a moment its orders count as seen.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(_badge('Pending'), findsNothing);
    expect(find.text('order n1'), findsOneWidget);
    // Confirmed hasn't been opened, so its badge stays.
    expect(_badge('Confirmed'), findsOneWidget);
    expect(await _seenStore.load(), containsPair('pending', 300));

    // A later order brings the Pending badge back.
    controller.add(_Snap([...old, _Doc('n3', 'pending', activity: 400)]));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: _badge('Pending'), matching: find.text('1')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('seen state is kept separately per role', (tester) async {
    SharedPreferences.setMockInitialValues({
      // The farmer has seen this order's activity; the buyer has not.
      'orders_seen_farmer_u1': '{"confirmed":500}',
      'orders_seen_buyer_u1': '{"confirmed":100}',
    });
    final snap = _Snap([_Doc('c1', 'confirmed', activity: 500)]);

    await tester.pumpWidget(_app(Stream.value(snap)));
    await tester.pumpAndSettle();
    expect(_badge('Confirmed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        Stream.value(snap),
        seenStore: const OrderSeenStore(uid: 'u1', role: 'buyer'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_badge('Confirmed'), findsOneWidget);
  });

  testWidgets('first time on a device, existing orders are not "new"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(Stream.value(_Snap([_Doc('p1', 'pending', activity: 900)]))),
    );
    await tester.pumpAndSettle();
    expect(_badge('Pending'), findsNothing);
    expect(await _seenStore.load(), containsPair('pending', 900));
  });

  testWidgets('swiping and tapping keep tab and page in sync', (tester) async {
    await tester.pumpWidget(_app(Stream.value(orders)));
    await tester.pumpAndSettle();
    final active = _labelColor(tester, 'Pending');
    expect(_labelColor(tester, 'Confirmed'), isNot(active));

    // Swipe left: Pending -> Confirmed.
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('order c1'), findsOneWidget);
    expect(_labelColor(tester, 'Confirmed'), active);
    expect(_labelColor(tester, 'Pending'), isNot(active));

    // Swipe left again: Shipped, which is empty.
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('No shipped orders yet'), findsOneWidget);
    expect(find.text('Shipped orders will appear here.'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);

    // Swipe right: back to Confirmed.
    await tester.fling(find.byType(TabBarView), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(_labelColor(tester, 'Confirmed'), active);

    // Tap goes straight to Completed.
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('order d0'), findsOneWidget);
    expect(_labelColor(tester, 'Completed'), active);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe tutorial: only for new users, only once', (tester) async {
    // Long-time user: never shown.
    await tester.pumpWidget(_app(Stream.value(orders)));
    await tester.pumpAndSettle();
    expect(find.text('Swipe between order statuses'), findsNothing);

    // New user: shown on first open, without blocking the orders.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(Stream.value(orders), newUser: true));
    // (The hint icon animates continuously, so pump frames, not settle.)
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Swipe between order statuses'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('order p1'));

    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Swipe between order statuses'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_tutorialKey), isTrue);

    // Opening Orders again: not shown.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(Stream.value(orders), newUser: true));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Swipe between order statuses'), findsNothing);
  });

  test('unseen activity is whatever the other party did', () {
    final t = Timestamp.fromMillisecondsSinceEpoch(1000);
    OrderInfo order(String status) =>
        OrderInfo('o1', {'status': status, 'createdAt': t, 'updatedAt': t});

    // A new order is news to the farmer, not to the buyer who placed it.
    expect(order('pending').unseenActivityMs(OrderRole.farmer), 1000);
    expect(order('pending').unseenActivityMs(OrderRole.buyer), 0);
    // Confirm / ship / complete are the farmer's own actions: news to the
    // buyer only.
    for (final status in ['confirmed', 'shipped', 'completed', 'rejected']) {
      expect(order(status).unseenActivityMs(OrderRole.buyer), 1000);
      expect(order(status).unseenActivityMs(OrderRole.farmer), 0);
    }
  });

  test('totals never guess an arranged delivery fee', () {
    final pickup = OrderInfo('a', {
      'deliveryMethod': 'pickup',
      'subtotal': 135,
    });
    expect(pickup.grandTotal, 135);

    final fixed = OrderInfo('b', {
      'deliveryMethod': 'delivery',
      'subtotal': 135,
      'deliveryFee': 50,
      'grandTotal': 185,
    });
    expect(fixed.grandTotal, 185);

    final arranged = OrderInfo('c', {
      'deliveryMethod': 'delivery',
      'subtotal': 135,
      'deliveryFee': null,
      'grandTotal': null,
    });
    expect(arranged.feeArranged, isTrue);
    expect(arranged.grandTotal, isNull);
  });
}
