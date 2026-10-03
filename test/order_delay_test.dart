import 'package:agritrade/services/order_format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp day(int d) => Timestamp.fromDate(DateTime(2026, 10, d));

void main() {
  test('the requested date is read under its new and its old name', () {
    expect(
      OrderInfo('a', {'requestedFulfillmentDate': day(20)}).neededBy,
      DateTime(2026, 10, 20),
    );
    expect(
      OrderInfo('a', {'neededBy': day(18)}).neededBy,
      DateTime(2026, 10, 18),
    );
    expect(const OrderInfo('a', {}).neededBy, isNull);
  });

  test('a proposed new date makes a confirmed order Delayed', () {
    final order = OrderInfo('a', {
      'status': 'confirmed',
      'delay': {
        'reason': 'weather',
        'note': ' Typhoon signal no. 2 ',
        'proposedDate': day(23),
        'status': 'proposed',
      },
    });
    expect(order.isDelayed, isTrue);
    // Still the same confirmed order underneath.
    expect(order.status, 'confirmed');
    expect(order.delayReasonLabel, 'Weather / Natural Disaster');
    expect(order.delayNote, 'Typhoon signal no. 2');
    expect(order.delayProposedDate, DateTime(2026, 10, 23));
  });

  test('once accepted it is no longer waiting, and has a confirmed date', () {
    final order = OrderInfo('a', {
      'status': 'confirmed',
      'confirmedFulfillmentDate': day(23),
      'delay': {
        'reason': 'supply',
        'proposedDate': day(23),
        'status': 'accepted',
      },
    });
    expect(order.isDelayed, isFalse);
    expect(order.delayAccepted, isTrue);
    expect(order.confirmedFulfillmentDate, DateTime(2026, 10, 23));
  });

  test('an order with no delay, or not confirmed, is never Delayed', () {
    expect(const OrderInfo('a', {'status': 'confirmed'}).isDelayed, isFalse);
    expect(
      const OrderInfo('a', {
        'status': 'shipped',
        'delay': {'status': 'proposed'},
      }).isDelayed,
      isFalse,
    );
  });

  test(
    'a cancelled order is the buyer\'s own doing, not unseen farmer news',
    () {
      final order = OrderInfo('a', {
        'status': 'cancelled',
        'cancelledAt': day(5),
      });
      expect(order.isCancelled, isTrue);
      expect(order.unseenActivityMs(OrderRole.buyer), 0);
      expect(order.unseenActivityMs(OrderRole.farmer), greaterThan(0));
    },
  );

  test('every reason has a label', () {
    expect(kOrderDelayReasons.keys, [
      'weather',
      'transport',
      'supply',
      'other',
    ]);
    expect(orderDelayReasonLabel('transport'), 'Road or Transportation Issue');
    expect(orderDelayReasonLabel('something else'), 'Delay');
  });
}
