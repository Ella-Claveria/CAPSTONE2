import 'package:agritrade/widgets/notification_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list(List<Widget> cards) => MaterialApp(
  home: Scaffold(
    body: ListView(padding: const EdgeInsets.all(16), children: cards),
  ),
);

// How readable a colour is on white: WCAG contrast ratio.
double _contrastOnWhite(Color color) =>
    1.05 / (color.computeLuminance() + 0.05);

void main() {
  final now = DateTime(2026, 10, 4, 10);

  test('groups by Today, Yesterday, then the date', () {
    expect(
      notificationGroupLabel(DateTime(2026, 10, 4, 0, 5), now: now),
      'Today',
    );
    expect(
      notificationGroupLabel(DateTime(2026, 10, 3, 23, 59), now: now),
      'Yesterday',
    );
    expect(
      notificationGroupLabel(DateTime(2026, 9, 28), now: now),
      'September 28',
    );
    expect(
      notificationGroupLabel(DateTime(2025, 12, 31), now: now),
      'December 31, 2025',
    );
  });

  test('filters: same for both roles, plus Reports for farmers', () {
    expect(notificationFiltersFor(isFarmer: false).map((f) => f.label), [
      'All',
      'Messages',
      'Orders',
      'Updates',
    ]);
    expect(notificationFiltersFor(isFarmer: true).last.label, 'Reports');
  });

  test('each real notification type lands under the right filter', () {
    NotificationFilter of(String type, {bool farmer = false}) =>
        notificationCategory(type, isFarmer: farmer);

    expect(of('chat_message'), NotificationFilter.messages);
    expect(of('new_order', farmer: true), NotificationFilter.orders);
    expect(of('order_status'), NotificationFilter.orders);
    expect(of('verification_status', farmer: true), NotificationFilter.updates);
    // Moderation notices: Reports for a farmer, Updates for a buyer (who
    // has no Reports filter).
    expect(of('moderation_warning', farmer: true), NotificationFilter.reports);
    expect(of('moderation_warning'), NotificationFilter.updates);
    expect(of('something_new'), NotificationFilter.updates);
  });

  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 1.4]) {
      testWidgets('no overflow at ${width.toInt()}px, text x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          _list([
            NotificationCard(
              type: 'order_status',
              title: 'Your order for Native Free-Range Chicken was confirmed',
              body:
                  'Maria Clara de los Santos-Villanueva confirmed your order of 12 kg liveweight. Tap to see the details and delivery date.',
              createdAt: now,
              isRead: false,
              onTap: () {},
            ),
            const SizedBox(height: 8),
            NotificationCard(
              type: 'moderation_warning',
              title: 'Listing Warning',
              body: '',
              createdAt: null,
              isRead: true,
            ),
          ]),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('title, message and time are dark enough to read', (
    tester,
  ) async {
    await tester.pumpWidget(
      _list([
        NotificationCard(
          type: 'chat_message',
          title: 'New Message',
          body: 'Is the kamote still available?',
          createdAt: now,
          isRead: true,
        ),
      ]),
    );
    for (final text in [
      'New Message',
      'Is the kamote still available?',
      '10:00 AM',
    ]) {
      final color = tester.widget<Text>(find.text(text)).style!.color!;
      // WCAG AA for normal text is 4.5:1.
      expect(_contrastOnWhite(color), greaterThan(4.5), reason: text);
    }
  });

  testWidgets('unread shows a dot; read does not', (tester) async {
    Finder dot() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          w.constraints?.maxWidth == 9,
    );

    await tester.pumpWidget(
      _list([
        NotificationCard(
          type: 'new_order',
          title: 'New Order',
          body: 'You have a new order.',
          createdAt: now,
          isRead: false,
        ),
      ]),
    );
    expect(dot(), findsOneWidget);

    await tester.pumpWidget(
      _list([
        NotificationCard(
          type: 'new_order',
          title: 'New Order',
          body: 'You have a new order.',
          createdAt: now,
          isRead: true,
        ),
      ]),
    );
    expect(dot(), findsNothing);
  });

  testWidgets('chevron only when the notification opens something', (
    tester,
  ) async {
    await tester.pumpWidget(
      _list([
        NotificationCard(
          type: 'order_status',
          title: 'Order Shipped',
          body: '',
          createdAt: now,
          isRead: true,
        ),
        NotificationCard(
          type: 'unknown_type',
          title: 'Notice',
          body: '',
          createdAt: now,
          isRead: true,
        ),
      ]),
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });
}
