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
        {'status': 'completed', 'total': 150, 'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 1)))},
        {'status': 'completed', 'total': 230, 'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 3)))},
        {'status': 'pending', 'total': 999, 'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 2)))},
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
  });
}
