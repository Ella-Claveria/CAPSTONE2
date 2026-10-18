import 'dart:convert';

import 'package:agritrade/services/order_format.dart';
import 'package:agritrade/services/order_receipt_service.dart';
import 'package:agritrade/widgets/order_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderInfo _order(String status, {String method = 'delivery', num? fee = 50}) {
  final placed = Timestamp.fromDate(DateTime(2026, 9, 27, 16, 28));
  return OrderInfo('k3f9qzAbCdEf', {
    'status': status,
    'productName': 'Tomato',
    'quantity': 3,
    'unit': 'kg',
    'quantityLabel': '3 kg',
    'pricingType': 'retail',
    'pricePerUnit': 45,
    'subtotal': 135,
    'total': 135,
    'deliveryMethod': method,
    'deliveryFee': fee,
    'grandTotal': method == 'delivery' && fee == null ? null : 135 + (fee ?? 0),
    'sellerId': 'farmer1',
    'sellerName': 'Test Farmer',
    'buyerId': 'buyer1',
    'buyerName': 'Test Buyer',
    'createdAt': placed,
    'updatedAt': placed,
    if (status == 'completed')
      'completedAt': Timestamp.fromDate(DateTime(2026, 9, 28, 9, 5)),
  });
}

Widget _card(OrderInfo order, OrderRole role) => MaterialApp(
  home: Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        OrderCard(order: order, role: role, isNew: true, onDetails: () {}),
      ],
    ),
  ),
);

void main() {
  test('order reference and receipt number share one code', () {
    final order = _order('completed');
    expect(order.displayId, 'AGR-2026-K3F9QZ');
    expect(receiptNumberFor(order.id, order.createdAt), 'RCT-2026-K3F9QZ');
  });

  testWidgets('farmer pending card fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_card(_order('pending'), OrderRole.farmer));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // no overflow
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('3 kg'), findsOneWidget);
    expect(find.text('RETAIL'), findsOneWidget);
    expect(find.text('₱45.00/kg'), findsOneWidget);
    // The farmer sees the buyer, and how the order is fulfilled.
    expect(find.text('Test Buyer · Delivery'), findsOneWidget);
    expect(find.text('Ordered Sep 27 · 4:28 PM'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('₱185.00'), findsOneWidget);
    // Only Details: Accept, Reject and messaging are in the order's details.
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.byKey(const ValueKey('order-new-dot')), findsOneWidget);
  });

  testWidgets('buyer card shows the farmer and no misleading total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(_order('shipped', fee: null), OrderRole.buyer),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Farmer · Delivery'), findsOneWidget);
    expect(find.text('Delivery in progress'), findsOneWidget);
    // Fee to be arranged: the product subtotal, labelled as such.
    expect(find.text('Subtotal + delivery'), findsOneWidget);
    expect(find.text('₱135.00'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('receipt PDF is built from the order record', (tester) async {
    final base = _order('completed', method: 'pickup', fee: null);
    // Fonts can't be downloaded in tests, so this also covers the offline
    // fallback coping with a name outside Latin-1.
    final order = OrderInfo(base.id, {
      ...base.data,
      'buyerName': 'Test Buyer ₱あ',
    });
    final receipt = OrderReceipt(
      order: order,
      receiptNumber: receiptNumberFor(order.id, order.createdAt),
      generatedAt: order.completedAt,
      sellerArea: 'Balakilong, Laurel',
    );
    expect(receipt.fileName, 'AgriTrade_Receipt_AGR-2026-K3F9QZ.pdf');

    final bytes = await tester.runAsync(
      () => OrderReceiptService.buildPdf(receipt),
    );
    expect(bytes, isNotNull);
    expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
  });
}
