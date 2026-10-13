// The Admin Portal's notification feed, built from the records the portal
// already loads, and the wording of a maintenance notice.
import 'package:agritrade/screen/admin_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 11, 12);

Timestamp at(int day, [int hour = 9]) =>
    Timestamp.fromDate(DateTime(2026, 10, day, hour));

List<AdminNotificationItem> feed({
  List<AdminRecord> orders = const [],
  List<AdminRecord> users = const [],
  List<AdminRecord> reports = const [],
  List<AdminRecord> announcements = const [],
}) => buildAdminNotifications(
  orders: orders,
  users: users,
  reports: reports,
  announcements: announcements,
  now: now,
);

void main() {
  test('an order shows when it was placed and how it ended', () {
    final items = feed(
      orders: [
        (
          id: 'o1',
          data: {
            'buyerName': 'Ana',
            'sellerName': 'Ben',
            'productName': 'Rice',
            'status': 'completed',
            'createdAt': at(9),
            'updatedAt': at(10),
            'completedAt': at(10),
          },
        ),
        (
          id: 'o2',
          data: {
            'buyerName': 'Cara',
            'sellerName': 'Ben',
            'productName': 'Corn',
            'status': 'shipped',
            'createdAt': at(8),
            'updatedAt': at(11, 8),
          },
        ),
      ],
    );
    expect(items.map((i) => i.title), [
      'Order shipped',
      'Order completed',
      'New order',
      'New order',
    ]);
    expect(items.last.detail, 'Cara ordered Corn from Ben');
    expect(
      items.every((i) => i.target == AdminNotificationTarget.transactions),
      isTrue,
    );
  });

  test('farmer applications, approvals and rejections are listed; admin '
      'accounts are not', () {
    final items = feed(
      users: [
        (
          id: 'f1',
          data: {
            'role': 'farmer',
            'fullName': 'Juan Cruz',
            'rsbaNumber': '123456789012345',
            'approvalStatus': 'approved',
            'createdAt': at(5),
            'reviewedAt': at(6),
          },
        ),
        (
          id: 'f2',
          data: {
            'role': 'farmer',
            'fullName': 'Old Farmer',
            'approvalStatus': 'rejected',
            'createdAt': at(7),
            'reviewedAt': at(7, 15),
          },
        ),
        (
          id: 'b1',
          data: {'role': 'buyer', 'fullName': 'Ana', 'createdAt': at(4)},
        ),
        (id: 'a1', data: {'role': 'admin', 'createdAt': at(4)}),
      ],
    );
    expect(items.map((i) => i.title), [
      'Farmer application rejected',
      'New farmer application',
      'Farmer approved',
      'New farmer application',
      'New buyer account',
    ]);
    expect(items[3].detail, 'Juan Cruz · RSBA No.: 123456789012345');
    expect(items[1].detail, contains('Not provided'));
  });

  test('reports and announcements are listed', () {
    final items = feed(
      reports: [
        (
          id: 'r1',
          data: {
            'issueType': 'Price Gouging',
            'reporterName': 'Ana',
            'createdAt': at(10),
          },
        ),
      ],
      announcements: [
        (
          id: 'n1',
          data: {
            'kind': 'maintenance',
            'title': 'Scheduled System Maintenance',
            'createdAt': at(11, 8),
          },
        ),
        (id: 'n2', data: {'title': 'Seed distribution', 'createdAt': at(9)}),
      ],
    );
    expect(items.map((i) => i.title), [
      'Maintenance notice sent',
      'New report',
      'Announcement sent',
    ]);
    expect(items[1].detail, 'Price Gouging · reported by Ana');
    expect(items[1].target, AdminNotificationTarget.moderation);
  });

  test('only the last 30 days, and nothing without a date', () {
    final items = feed(
      orders: [
        (
          id: 'old',
          data: {
            'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
            'status': 'pending',
          },
        ),
        (id: 'undated', data: {'status': 'confirmed'}),
      ],
    );
    expect(items, isEmpty);
  });

  test('a maintenance notice states its window', () {
    expect(
      maintenanceNoticeBody(
        DateTime(2026, 10, 12, 22),
        DateTime(2026, 10, 12, 23, 30),
        ' Please finish open orders first. ',
      ),
      'AgriTrade+ will be under maintenance on Oct 12, 2026, 10:00 PM to '
      '11:30 PM. The app may be unavailable or slow during this time. '
      'Please finish open orders first.',
    );
    expect(
      maintenanceNoticeBody(
        DateTime(2026, 10, 12, 22),
        DateTime(2026, 10, 13, 2),
        '',
      ),
      'AgriTrade+ will be under maintenance on Oct 12, 2026, 10:00 PM to '
      'Oct 13, 2026, 2:00 AM. The app may be unavailable or slow during '
      'this time.',
    );
  });

  test('times read naturally', () {
    expect(adminNotificationTime(now, now), 'Just now');
    expect(
      adminNotificationTime(now.subtract(const Duration(minutes: 5)), now),
      '5m ago',
    );
    expect(
      adminNotificationTime(now.subtract(const Duration(hours: 3)), now),
      '3h ago',
    );
    expect(
      adminNotificationTime(now.subtract(const Duration(days: 2)), now),
      '2d ago',
    );
    expect(adminNotificationTime(DateTime(2026, 9, 20), now), 'Sep 20');
  });
}
