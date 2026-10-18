// The order card, the same for farmers and buyers: the status tag on the
// card's right edge, and only the total and Details at the bottom — the
// order's actions and messaging are in its details.
import 'package:agritrade/services/order_format.dart';
import 'package:agritrade/widgets/order_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  const order = OrderInfo('o1', {
    'productName': 'Cassava',
    'status': 'confirmed',
    'buyerName': 'Junior Pesigan',
    'sellerName': 'Ellen Gonzales',
  });

  for (final role in OrderRole.values) {
    testWidgets('${role.name}: tag on the right edge, Details at the bottom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderCard(
              order: order,
              role: role,
              onDetails: () => opened++,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(OrderCard));
      final tag = tester.getRect(find.byType(OrderStatusTag));
      final details = tester.getRect(
        find.widgetWithText(TextButton, 'Details'),
      );
      // Both end on the card's inner edge (12 px padding).
      expect(tag.right, moreOrLessEquals(card.right - 13, epsilon: 1));
      expect(details.right, moreOrLessEquals(tag.right, epsilon: 1));
      // No message icon or action buttons on the card.
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(find.text('Report Delay'), findsNothing);

      await tester.tap(find.text('Details'));
      expect(opened, 1);
    });
  }
}
