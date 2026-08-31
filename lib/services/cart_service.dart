import 'package:flutter/material.dart';

// App-wide cart that remembers how many kilos were added per product.
class CartService {
  CartService._();
  static final CartService instance = CartService._();

  // productId -> kilos
  final Map<String, int> _items = {};

  // Total kilos across all products (for any badge that wants it).
  final ValueNotifier<int> totalKilos = ValueNotifier<int>(0);

  int countFor(String productId) => _items[productId] ?? 0;

  void setCount(String productId, int kilos) {
    if (kilos <= 0) {
      _items.remove(productId);
    } else {
      _items[productId] = kilos;
    }
    _recalculate();
  }

  void _recalculate() {
    int sum = 0;
    for (final v in _items.values) {
      sum += v;
    }
    totalKilos.value = sum;
  }

  void clear() {
    _items.clear();
    totalKilos.value = 0;
  }
}
