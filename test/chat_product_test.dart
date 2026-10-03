import 'package:agritrade/screen/chat_product_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatProduct.fromData', () {
    test('wholesale enabled exposes wholesale price and minimum', () {
      final p = ChatProduct.fromData('p1', {
        'name': 'Cassava',
        'unit': 'kg',
        'farmerId': 'f1',
        'retailPrice': 35,
        'wholesaleEnabled': true,
        'wholesalePrice': 30,
        'wholesaleMinimumQuantity': 20,
        'quantity': 100,
      });
      expect(p.wholesaleEnabled, isTrue);
      expect(p.wholesalePrice, 30);
      expect(p.wholesaleMinimum, 20);
      expect(p.priceFor('wholesale'), 30);
      expect(p.priceFor('retail'), 35);
      expect(p.orderable, isTrue);
    });

    test('wholesale disabled hides wholesale even if old values remain', () {
      final p = ChatProduct.fromData('p1', {
        'name': 'Cassava',
        'retailPrice': 35,
        'wholesaleEnabled': false,
        'wholesalePrice': 30,
        'wholesaleMinimumQuantity': 20,
        'quantity': 5,
      });
      expect(p.wholesaleEnabled, isFalse);
      expect(p.wholesalePrice, isNull);
      expect(p.wholesaleMinimum, isNull);
    });

    test('falls back to price field and commodity unit', () {
      final p = ChatProduct.fromData('p1', {
        'name': 'Cassava',
        'price': 40,
        'quantity': 1,
      });
      expect(p.retailPrice, 40);
      expect(p.unit, isNotEmpty);
    });

    test('archived, suspended or out-of-stock listings are not orderable', () {
      final base = {'name': 'Cassava', 'retailPrice': 35, 'quantity': 10};
      expect(
        ChatProduct.fromData('p', {...base, 'isArchived': true}).orderable,
        isFalse,
      );
      expect(
        ChatProduct.fromData('p', {...base, 'isSuspended': true}).orderable,
        isFalse,
      );
      expect(
        ChatProduct.fromData('p', {...base, 'quantity': 0}).orderable,
        isFalse,
      );
    });
  });
}
