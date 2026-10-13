import 'package:agritrade/data/commodity_master_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = CommodityRegistry.instance;

  // Back to the default set after each test.
  tearDown(() => registry.applyAdminRecords(const []));

  test('a commodity the Admin adds appears under its category', () {
    expect(registry.find('Tomato'), isNull);

    registry.applyAdminRecords([
      {
        'name': 'Tomato',
        'category': 'Vegetables',
        'unit': 'kg',
        'isActive': true,
      },
    ]);

    expect(registry.activeByCategory['Vegetables'], contains('Tomato'));
    expect(registry.activeNames, contains('Tomato'));
    expect(categoryOfCommodity('tomato'), 'Vegetables');
    expect(matchSupportedCommodity('Fresh Tomato', activeOnly: true), 'Tomato');
    expect(unitForProductName('Tomato'), 'kg');
  });

  test('a new category appears on its own', () {
    registry.applyAdminRecords([
      {'name': 'Honey', 'category': 'Bee Products', 'unit': 'piece'},
    ]);

    expect(registry.activeByCategory['Bee Products'], ['Honey']);
    expect(registry.categories, contains('Bee Products'));
    expect(isCountBasedUnit(unitForCommodity('Honey')), isTrue);
  });

  test('a disabled commodity cannot be chosen but is still recognized', () {
    registry.applyAdminRecords([
      {'name': 'Eggplant', 'category': 'Vegetables', 'isActive': false},
    ]);

    // Gone from Supported Products and the Add Product suggestions…
    expect(registry.activeNames, isNot(contains('Eggplant')));
    expect(
      registry.activeByCategory['Vegetables'],
      isNot(contains('Eggplant')),
    );
    expect(matchSupportedCommodity('Eggplant', activeOnly: true), isNull);
    // …but existing listings keep their category and unit.
    expect(matchSupportedCommodity('Eggplant'), 'Eggplant');
    expect(categoryOfCommodity('Eggplant'), 'Vegetables');
    expect(unitForCommodity('Eggplant'), 'kg');
  });

  test('the Admin record wins over the default; odd units fall back', () {
    registry.applyAdminRecords([
      {'name': 'Coconut', 'category': 'Tree Crops', 'unit': 'kilogram'},
      // A price record with no category isn't a postable commodity.
      {'name': 'Mystery Item', 'baselinePrice': 10},
    ]);

    expect(categoryOfCommodity('Coconut'), 'Tree Crops');
    expect(unitForCommodity('Coconut'), 'piece'); // default unit kept
    expect(registry.find('Mystery Item'), isNull);
  });

  test('a commodity the Admin does not have is not on the list, even a '
      'default one', () {
    registry.applyAdminRecords([
      {'name': 'Rice', 'category': 'Grains', 'unit': 'kg'},
      // No category of its own: borrowed from the default of that name.
      {'name': 'Corn'},
    ]);

    expect(registry.activeNames, ['Rice', 'Corn']);
    expect(categoryOfCommodity('Corn'), 'Grains');
    // Deleted by the Admin, or never added: gone, though it is a default.
    expect(registry.find('Cattle'), isNull);
    expect(registry.activeByCategory.keys, isNot(contains('Livestock')));
  });

  test('defaults stay available until the Admin overrides them', () {
    expect(registry.activeByCategory.keys, contains('Livestock'));
    expect(unitForCommodity('Cattle'), 'head');
    expect(matchSupportedCommodity('Native Chicken'), 'Chicken');
  });
}
