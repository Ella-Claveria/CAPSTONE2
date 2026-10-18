// Livestock is sold live (in the commodity's own unit) or slaughtered (per
// kg) — for every commodity the Admin files under Livestock.
import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Swine', 'category': 'Livestock', 'unit': 'kg liveweight'},
      {'name': 'Cattle', 'category': 'Livestock', 'unit': 'head'},
      {'name': 'Goat', 'category': 'livestock', 'unit': 'head'},
      {'name': 'Okra', 'category': 'Vegetables', 'unit': 'kg'},
    ]);
  });

  test('every Admin livestock commodity counts, whatever the capitals', () {
    expect(isLivestockCategory(categoryOfCommodity('Goat')), isTrue);
    expect(isLivestockCategory(categoryOfCommodity('Swine')), isTrue);
    expect(isLivestockCategory(categoryOfCommodity('Okra')), isFalse);
  });

  test('live keeps the commodity unit; slaughtered is per kg', () {
    expect(unitForListing('Swine', SellingOption.live), 'kg liveweight');
    expect(unitForListing('Cattle', SellingOption.live), 'head');
    expect(unitForListing('Cattle', SellingOption.slaughtered), 'kg');
    expect(unitForListing('Okra', null), 'kg');
  });

  test('the saved option reads back; none saved is no option', () {
    expect(
      sellingOptionOf({'sellingOption': 'slaughtered'}),
      SellingOption.slaughtered,
    );
    expect(sellingOptionOf({'sellingOption': 'live'}), SellingOption.live);
    expect(sellingOptionOf({}), isNull);
    expect(isSlaughtered({'sellingOption': 'slaughtered'}), isTrue);
    expect(isSlaughtered({}), isFalse);
  });

  test('the name shows how it is sold', () {
    expect(
      withSellingOption('Swine', {'sellingOption': 'live'}),
      'Swine (Live)',
    );
    expect(
      withSellingOption('Cattle', {'sellingOption': 'slaughtered'}),
      'Cattle (Slaughtered)',
    );
    expect(withSellingOption('Okra', {}), 'Okra');
  });

  test('an order names the product with its selling option', () {
    expect(
      const OrderInfo('o1', {
        'productName': 'Swine',
        'sellingOption': 'slaughtered',
      }).productName,
      'Swine (Slaughtered)',
    );
    expect(const OrderInfo('o2', {'productName': 'Okra'}).productName, 'Okra');
  });
}
