import 'package:agritrade/services/product_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'share text carries the listing basics and the link, nothing private',
    () {
      final text = productShareText(
        name: 'Tomato',
        price: 45,
        unit: 'kg',
        quantity: 25,
        location: 'Laurel, Batangas',
        link: productLink('abc123XYZ'),
      );

      expect(
        text,
        'Tomato available on AgriTrade+\n'
        '₱45.00/kg\n'
        'Available Stock: 25 kg\n'
        'Location: Laurel, Batangas\n'
        'View Product: https://agritrade-bef87.web.app/product/abc123XYZ',
      );
    },
  );

  test('out-of-stock and unknown location are handled', () {
    final text = productShareText(
      name: 'Coconut',
      price: 30,
      unit: 'piece',
      quantity: 0,
      location: '',
      link: productLink('p1'),
    );
    expect(text, contains('Currently out of stock'));
    expect(text, isNot(contains('Location:')));
  });

  test('a shared link resolves back to its product id', () {
    expect(productIdFromLink(productLink('abc123XYZ')), 'abc123XYZ');
    expect(
      productIdFromLink(Uri.parse('agritrade://product/abc123XYZ')),
      'abc123XYZ',
    );
    expect(
      productIdFromLink(
        Uri.parse('https://agritrade-bef87.web.app/product/abc123XYZ?utm=x'),
      ),
      'abc123XYZ',
    );
  });

  test('other links, and ids that are not ids, are ignored', () {
    expect(
      productIdFromLink(Uri.parse('https://agritrade-bef87.web.app/')),
      isNull,
    );
    expect(
      productIdFromLink(
        Uri.parse('https://agritrade-bef87.web.app/orders/abc'),
      ),
      isNull,
    );
    expect(
      productIdFromLink(
        Uri.parse('https://agritrade-bef87.web.app/product/..%2Fusers%2Fx'),
      ),
      isNull,
    );
  });

  test('Share My Store lists up to five products with their links', () {
    final products = [
      for (var i = 1; i <= 7; i++)
        (name: 'Crop $i', price: 40 + i, unit: 'kg', link: productLink('p$i')),
    ];
    final text = storeShareText(
      farmerName: 'Juan Dela Cruz',
      location: 'Laurel, Batangas',
      products: products,
      total: 7,
    );
    expect(
      text,
      startsWith('Juan Dela Cruz on AgriTrade+\nLocation: Laurel, Batangas\n'),
    );
    expect(
      text,
      contains(
        '• Crop 1 — ₱41.00/kg\n'
        '  https://agritrade-bef87.web.app/product/p1',
      ),
    );
    expect(text, contains('Crop 5'));
    expect(text, isNot(contains('Crop 6')));
    expect(text, endsWith('And 2 more — find Juan Dela Cruz on AgriTrade+.'));

    // A short store: no 'more' line.
    expect(
      storeShareText(
        farmerName: 'Ana',
        location: '',
        products: products.take(2).toList(),
      ),
      isNot(contains('more')),
    );
  });
}
