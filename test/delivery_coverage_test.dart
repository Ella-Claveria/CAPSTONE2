import 'package:agritrade/services/delivery_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product(Map<String, dynamic> coverage) => {
  'deliveryAvailable': true,
  'deliveryCoverage': {
    'originBarangay': 'Bugaan East',
    'originMunicipality': 'Laurel',
    'originProvince': 'Batangas',
    ...coverage,
  },
};

void main() {
  const manila = BuyerArea(
    barangay: 'Barangay 123',
    city: 'City of Manila',
    province: 'National Capital Region (NCR)',
  );
  const laurelSame = BuyerArea(
    barangay: 'Bugaan East',
    city: 'Laurel',
    province: 'Batangas',
  );
  const laurelOther = BuyerArea(
    barangay: 'Ticub',
    city: 'Laurel',
    province: 'Batangas',
  );
  const tanauan = BuyerArea(
    barangay: 'Poblacion',
    city: 'City of Tanauan',
    province: 'Batangas',
  );

  group('reach', () {
    test('Same Barangay covers only the farm barangay', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'sameBarangay', 'feeType': 'arranged'}),
      );
      expect(c.reach(laurelSame), DeliveryReach.covered);
      expect(c.reach(laurelOther), DeliveryReach.outside);
    });

    test('Within Municipality covers the farm town only', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'municipality', 'feeType': 'fixed', 'fee': 50}),
      );
      expect(c.reach(laurelOther), DeliveryReach.covered);
      expect(c.reach(tanauan), DeliveryReach.outside);
      expect(c.reach(manila), DeliveryReach.outside);
    });

    test('Nearby includes neighbouring towns, spelled either way', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'nearby', 'feeType': 'arranged'}),
      );
      expect(c.reach(tanauan), DeliveryReach.covered);
      expect(
        c.reach(const BuyerArea(city: 'Tagaytay City', province: 'Cavite')),
        DeliveryReach.covered,
      );
      expect(c.reach(manila), DeliveryReach.outside);
    });

    test('Custom areas match by name and province', () {
      final c = DeliveryCoverage.fromProduct(
        product({
          'type': 'custom',
          'feeType': 'fixed',
          'fee': 80,
          'areas': [
            {'name': 'Batangas City', 'province': 'Batangas'},
            {'name': 'City of Manila', 'province': 'Metro Manila'},
          ],
        }),
      );
      expect(
        c.reach(const BuyerArea(city: 'Batangas', province: 'Batangas')),
        DeliveryReach.covered,
      );
      expect(c.reach(manila), DeliveryReach.covered);
      expect(c.reach(laurelOther), DeliveryReach.outside);
    });

    test('unknown buyer location cannot be checked', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'municipality', 'feeType': 'arranged'}),
      );
      expect(c.reach(const BuyerArea()), DeliveryReach.unknownLocation);
    });

    test('Delivery Available without coverage is not nationwide', () {
      final c = DeliveryCoverage.fromProduct({'deliveryAvailable': true});
      expect(c.configured, isFalse);
      expect(c.reach(laurelOther), DeliveryReach.covered);
      expect(c.reach(manila), DeliveryReach.outside);
      expect(c.feeKnown, isFalse);
    });
  });

  group('fee', () {
    test('fixed fee is known and labelled in pesos', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'municipality', 'feeType': 'fixed', 'fee': 50}),
      );
      expect(c.feeKnown, isTrue);
      expect(c.feeLabel, contains('50'));
    });

    test('fixed without an amount falls back to to-be-arranged', () {
      final c = DeliveryCoverage.fromProduct(
        product({'type': 'municipality', 'feeType': 'fixed'}),
      );
      expect(c.feeKnown, isFalse);
      expect(c.feeLabel, 'To be arranged with seller');
    });
  });

  test('toMap round-trips', () {
    const original = DeliveryCoverage(
      type: DeliveryCoverageType.custom,
      customAreas: [DeliveryArea('Talisay', 'Batangas')],
      feeType: DeliveryFeeType.fixed,
      fee: 40,
      originBarangay: 'Ticub',
    );
    final copy = DeliveryCoverage.fromProduct({
      'deliveryCoverage': original.toMap(),
    });
    expect(copy.type, DeliveryCoverageType.custom);
    expect(copy.customAreas, original.customAreas);
    expect(copy.fee, 40);
    expect(copy.originBarangay, 'Ticub');
    expect(copy.origin, kDefaultFarmOrigin);
  });

  test('place names normalize', () {
    expect(normalizePlace('City of Tanauan'), normalizePlace('Tanauan City'));
    expect(
      normalizeBarangay('Barangay 1 (Pob.)'),
      normalizeBarangay('Brgy. 1'),
    );
    expect(
      normalizeProvince('National Capital Region (NCR)'),
      normalizeProvince('Metro Manila'),
    );
  });
}
