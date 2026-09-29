import 'package:flutter_test/flutter_test.dart';
import 'package:agritrade/services/pricing_tier_service.dart';

void main() {
  group('PricingTierService', () {
    test('uses retail below wholesale minimum', () {
      final quote = PricingTierService.quote(
        quantity: 10,
        retailPrice: 75,
        wholesaleEnabled: true,
        wholesalePrice: 68,
        wholesaleMinimumQuantity: 20,
      );

      expect(quote.pricingType, 'retail');
      expect(quote.unitPrice, 75);
      expect(quote.subtotal, 750);
      expect(quote.quantityToWholesale, 10);
    });

    test('switches to wholesale exactly at minimum', () {
      final quote = PricingTierService.quote(
        quantity: 20,
        retailPrice: 75,
        wholesaleEnabled: true,
        wholesalePrice: 68,
        wholesaleMinimumQuantity: 20,
      );

      expect(quote.pricingType, 'wholesale');
      expect(quote.unitPrice, 68);
      expect(quote.subtotal, 1360);
      expect(quote.quantityToWholesale, 0);
    });

    test('keeps wholesale above minimum', () {
      final quote = PricingTierService.quote(
        quantity: 25,
        retailPrice: 75,
        wholesaleEnabled: true,
        wholesalePrice: 68,
        wholesaleMinimumQuantity: 20,
      );

      expect(quote.pricingType, 'wholesale');
      expect(quote.subtotal, 1700);
    });

    test('wholesale-disabled listing always uses retail', () {
      final quote = PricingTierService.quote(
        quantity: 100,
        retailPrice: 75,
        wholesaleEnabled: false,
        wholesalePrice: 68,
        wholesaleMinimumQuantity: 20,
      );

      expect(quote.pricingType, 'retail');
      expect(quote.unitPrice, 75);
      expect(quote.subtotal, 7500);
      expect(quote.quantityToWholesale, isNull);
    });

    test('supports decimal weight quantities', () {
      final quote = PricingTierService.quote(
        quantity: 20.5,
        retailPrice: 75,
        wholesaleEnabled: true,
        wholesalePrice: 68,
        wholesaleMinimumQuantity: 20,
      );

      expect(quote.pricingType, 'wholesale');
      expect(quote.subtotal, 1394);
    });
  });
}
