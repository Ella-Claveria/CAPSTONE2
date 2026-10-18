import 'package:agritrade/screen/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('low stock is 20% or less of the stock the farmer last set', () {
    expect(stockStatusOf(0, baseline: 100), StockStatus.outOfStock);
    expect(stockStatusOf(20, baseline: 100), StockStatus.lowStock);
    expect(stockStatusOf(21, baseline: 100), StockStatus.inStock);
    // A big harvest warns early, not at the last few kilos.
    expect(stockStatusOf(200, baseline: 1000), StockStatus.lowStock);
    expect(stockStatusOf(500, baseline: 1000), StockStatus.inStock);
    // Whole animals round up: 10 head → low at 2; 3 head → low at 1.
    expect(stockStatusOf(2, baseline: 10, unit: 'head'), StockStatus.lowStock);
    expect(stockStatusOf(3, baseline: 10, unit: 'head'), StockStatus.inStock);
    expect(stockStatusOf(1, baseline: 3, unit: 'head'), StockStatus.lowStock);
    expect(stockStatusOf(2, baseline: 3, unit: 'head'), StockStatus.inStock);
  });

  test('older listings with no baseline use a minimum per unit', () {
    expect(stockStatusOf(10), StockStatus.lowStock);
    expect(stockStatusOf(11), StockStatus.inStock);
    expect(stockStatusOf(2, unit: 'head'), StockStatus.lowStock);
    expect(stockStatusOf(3, unit: 'head'), StockStatus.inStock);
    expect(
      stockStatusOfProduct({
        'quantity': 15,
        'stockBaseline': 100,
        'unit': 'kg',
      }),
      StockStatus.lowStock,
    );
  });

  test('sold quantity counts completed orders only, per product', () {
    final sold = soldByProduct([
      {'status': 'completed', 'productId': 'tomato', 'quantity': 20},
      {'status': 'completed', 'productId': 'tomato', 'quantity': 15},
      {'status': 'completed', 'productId': 'onion', 'quantity': 2.5},
      // Not sold: still in progress, or rejected (stock was returned).
      {'status': 'pending', 'productId': 'tomato', 'quantity': 4},
      {'status': 'shipped', 'productId': 'tomato', 'quantity': 4},
      {'status': 'rejected', 'productId': 'tomato', 'quantity': 4},
    ]);
    expect(sold, {'tomato': 35, 'onion': 2.5});
  });
}
