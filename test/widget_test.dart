import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agritrade/services/farmer_revenue_service.dart';

void main() {
  group('Farmer revenue periods', () {
    test('beginner farmers default to weekly revenue for the first 7 days', () {
      final now = DateTime(2026, 8, 18, 12, 0, 0);
      final registeredAt = now.subtract(const Duration(days: 2));

      expect(
        FarmerRevenueService.resolveView(registeredAt: registeredAt, now: now),
        FarmerRevenueView.weekly,
      );
    });

    test('farmers older than 7 days can use monthly revenue', () {
      final now = DateTime(2026, 8, 18, 12, 0, 0);
      final registeredAt = now.subtract(const Duration(days: 10));

      expect(
        FarmerRevenueService.resolveView(registeredAt: registeredAt, now: now),
        FarmerRevenueView.monthly,
      );
    });

    test('completed orders are summed for the selected revenue range', () {
      final now = DateTime(2026, 8, 18, 12, 0, 0);
      final orders = [
        {
          'status': 'completed',
          'total': 150,
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 1)),
          ),
        },
        {
          'status': 'completed',
          'total': 230,
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 3)),
          ),
        },
        {
          'status': 'pending',
          'total': 999,
          'createdAt': Timestamp.fromDate(
            now.subtract(const Duration(days: 2)),
          ),
        },
      ];

      expect(
        FarmerRevenueService.totalRevenueForRange(
          orders: orders,
          view: FarmerRevenueView.weekly,
          now: now,
        ),
        380,
      );
    });

    test('marketplace best sellers rank completed quantity across sellers', () {
      final sales = [
        {
          'status': 'completed',
          'productName': 'Rice',
          'quantity': 20,
          'unit': 'kg',
        },
        {
          'status': 'completed',
          'productName': 'rice',
          'quantity': 15,
          'unit': 'kg',
        },
        {
          'status': 'completed',
          'productName': 'Corn',
          'quantity': 25,
          'unit': 'kg',
        },
        {
          'status': 'completed',
          'productName': 'Eggplant',
          'quantity': 10,
          'unit': 'kg',
        },
        {
          'status': 'pending',
          'productName': 'Eggplant',
          'quantity': 100,
          'unit': 'kg',
        },
      ];

      final result = FarmerRevenueService.topMarketplaceProducts(sales: sales);

      expect(result.map((product) => product.name), [
        'Rice',
        'Corn',
        'Eggplant',
      ]);
      expect(result.first.quantity, 35);
      expect(result.first.orderCount, 2);
    });

    test('marketplace best sellers keep different units separate', () {
      final result = FarmerRevenueService.topMarketplaceProducts(
        sales: [
          {
            'status': 'completed',
            'productName': 'Coconut',
            'quantity': 8,
            'unit': 'piece',
          },
          {
            'status': 'completed',
            'productName': 'Coconut',
            'quantity': 5,
            'unit': 'kg',
          },
        ],
      );

      expect(result, hasLength(2));
      expect(result.map((product) => product.quantity), [8, 5]);
    });
  });
}
