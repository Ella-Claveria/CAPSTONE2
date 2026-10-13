// Sales by Category: where a completed order's category comes from.
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const category = DashboardAnalyticsService.orderCategory;

  test('the category frozen on the order wins over the listing', () {
    expect(
      category({'category': 'Fruits'}, {'category': 'Vegetables'}),
      'Fruits',
    );
  });

  test('however it was typed, it lands under the one category', () {
    expect(category({'category': ' root crops '}, null), 'Root Crops');
    expect(category({'category': 'VEGETABLES'}, null), 'Vegetables');
    expect(category({'category': 'livestock'}, null), 'Livestock');
  });

  test('an order without one takes its listing\'s category', () {
    expect(
      category({'productName': 'Lakatan'}, {'category': 'Fruits'}),
      'Fruits',
    );
    expect(category({'category': '  '}, {'category': 'Spices'}), 'Spices');
  });

  test('otherwise the commodity it names, matched exactly', () {
    expect(category({'commodity': 'Banana'}, null), 'Fruits');
    expect(category({}, {'commodity': 'Swine'}), 'Livestock');
    expect(category({'productName': 'rice'}, null), 'Grains');
  });

  test('a listing name that refers to a commodity takes its category', () {
    expect(category({'productName': 'Yellow Corn'}, null), 'Grains');
    expect(category({'productName': 'Native Chicken'}, null), 'Livestock');
  });

  test('a category outside the commodity list is not used', () {
    expect(
      category({'category': 'Poultry', 'productName': 'Chicken'}, null),
      'Livestock',
    );
    expect(
      category({'category': 'Poultry', 'productName': 'Box'}, null),
      isNull,
    );
  });

  test('nothing recorded gives no category rather than a guess', () {
    expect(category({'productName': 'Fresh Native Tomato'}, null), isNull);
    expect(category({'productName': 'Mystery Box'}, {'name': 'Box'}), isNull);
    expect(category({}, null), isNull);
  });

  test('every supported category is reported under its own name', () {
    for (final name in DashboardAnalyticsService.salesCategories) {
      expect(category({'category': name.toLowerCase()}, null), name);
    }
  });
}
