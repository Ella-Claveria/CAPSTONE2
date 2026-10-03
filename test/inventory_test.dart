import 'package:agritrade/screen/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock status follows the available quantity', () {
    expect(stockStatusOf(0), StockStatus.outOfStock);
    expect(stockStatusOf(0.5), StockStatus.lowStock);
    expect(stockStatusOf(kLowStockThreshold), StockStatus.lowStock);
    expect(stockStatusOf(kLowStockThreshold + 1), StockStatus.inStock);
    expect(stockStatusOf(15), StockStatus.inStock);
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
