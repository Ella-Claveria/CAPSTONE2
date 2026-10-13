// The Admin features added to close gaps in the system's objectives: the
// Transactions list, User Accounts verification, buyer searches by area,
// and a per-commodity price movement.
import 'package:agritrade/screen/admin_transactions_view.dart';
import 'package:agritrade/screen/admin_user_accounts_view.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:agritrade/services/rsba_number.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp at(int year, int month, int day) =>
    Timestamp.fromDate(DateTime(year, month, day));

void main() {
  group('transactions', () {
    final rows = buildTransactionRows([
      (
        id: 'order-aaaaaaaa1',
        data: {
          'status': 'completed',
          'buyerName': 'Ana Reyes',
          'sellerName': 'Mang Jose',
          'productName': 'Tomato',
          'quantity': 5,
          'unit': 'kg',
          'total': 250,
          'deliveryMethod': 'pickup',
          'createdAt': at(2026, 10, 1),
        },
      ),
      (
        id: 'order-bbbbbbbb2',
        data: {
          'status': 'Pending',
          'buyerName': 'Ben Cruz',
          'sellerName': 'Aling Rosa',
          'productName': 'Eggplant',
          'quantityLabel': '3 kg',
          'total': 90,
          'grandTotal': 120,
          'createdAt': at(2026, 10, 9),
        },
      ),
      (
        id: 'order-cccccccc3',
        data: {
          'status': 'cancelled',
          'productName': 'Rice',
          'createdAt': at(2026, 9, 2),
        },
      ),
    ]);

    test('every order is listed, newest first', () {
      expect(rows.map((r) => r.product), ['Eggplant', 'Tomato', 'Rice']);
    });

    test('each row carries who, what, how much and its status', () {
      final tomato = rows[1];
      expect(tomato.buyer, 'Ana Reyes');
      expect(tomato.seller, 'Mang Jose');
      expect(tomato.quantity, '5 kg');
      expect(tomato.total, 250);
      expect(tomato.statusLabel, 'Completed');
      expect(tomato.isCompleted, isTrue);
      // The amount charged, delivery fee included, when there is one.
      expect(rows.first.total, 120);
      expect(rows.first.quantity, '3 kg');
      expect(rows.first.statusLabel, 'Pending');
      expect(rows.first.isInProgress, isTrue);
      expect(rows.last.isClosedWithoutSale, isTrue);
    });

    test('search covers order ID, buyer, farmer and product', () {
      expect(rows.where((r) => r.matches('ana')).single.product, 'Tomato');
      expect(rows.where((r) => r.matches('ROSA')).single.product, 'Eggplant');
      expect(rows.where((r) => r.matches('cccc')).single.product, 'Rice');
      expect(rows.where((r) => r.matches('')).length, 3);
      expect(rows.where((r) => r.matches('nothing')), isEmpty);
    });
  });

  group('user accounts', () {
    final rows = buildAccountRows([
      (
        id: 'b1',
        data: {
          'role': 'buyer',
          'fullName': 'Ana Reyes',
          'email': 'ana@example.com',
          'emailOtpVerified': true,
          'barangay': 'Sambat',
          'municipality': 'Tanauan',
          'createdAt': at(2026, 9, 1),
        },
      ),
      (
        id: 'b2',
        data: {
          'role': 'buyer',
          'fullName': 'Ben Cruz',
          'accountStatus': 'suspended',
          'createdAt': at(2026, 10, 1),
        },
      ),
      (id: 'f1', data: {'role': 'farmer', 'approvalStatus': 'approved'}),
      (id: 'f2', data: {'role': 'farmer'}),
      (id: 'f3', data: {'role': 'farmer', 'approvalStatus': 'rejected'}),
      (id: 'a1', data: {'role': 'admin', 'fullName': 'Officer'}),
    ]);
    AdminAccountRow row(String uid) => rows.firstWhere((r) => r.uid == uid);

    test('lists buyers and farmers, never admin accounts', () {
      expect(rows.length, 5);
      expect(rows.any((r) => r.uid == 'a1'), isFalse);
      // Newest registration first.
      expect(rows.first.uid, 'b2');
    });

    test('a buyer has no application; only the email is verified', () {
      expect(row('b1').identity, isNull);
      expect(row('b2').identity, isNull);
      expect(row('b1').emailVerified, isTrue);
      expect(row('b2').emailVerified, isFalse);
      expect(row('b1').area, 'Sambat, Tanauan');
      expect(row('b2').accountStatus, 'suspended');
    });

    test('a buyer\'s email is partly hidden, a farmer\'s is not', () {
      expect(row('b1').displayEmail, 'a***@example.com');
      expect(row('b1').matches('ana@example.com'), isFalse);
      expect(row('b1').matches('example.com'), isTrue);
      expect(maskEmail('jo@mail.com'), 'j***@mail.com');
      expect(maskEmail('not an email'), '***');
      expect(maskEmail(''), '');
      final farmer = AdminAccountRow.fromUser('f9', {
        'role': 'farmer',
        'email': 'farmer@example.com',
      })!;
      expect(farmer.displayEmail, 'farmer@example.com');
    });

    test('a farmer\'s identity follows their application', () {
      expect(row('f1').identity, AccountIdentity.verified);
      expect(row('f2').identity, AccountIdentity.pendingReview);
      expect(row('f3').identity, AccountIdentity.rejected);
    });
  });

  group('farmer ID', () {
    test('is the RSBA number the farmer registered with', () {
      expect(
        farmerIdOf({'rsbaNumber': ' ab12345678901234 '}),
        'AB12345678901234',
      );
      // The verification record carries it when the profile does not.
      expect(
        farmerIdOf({}, {'rsbaNumber': '123456789012345'}),
        '123456789012345',
      );
      expect(farmerIdOf({'rsbaNumber': 'A'}, {'rsbaNumber': 'B'}), 'A');
    });

    test('is never made up for a farmer with no number on file', () {
      expect(farmerIdOf({'fullName': 'Old Farmer'}), isNull);
      expect(farmerIdOf({'rsbaNumber': '  '}, null), isNull);
      expect(farmerIdOf(null), isNull);
    });
  });

  group('buyer searches by area', () {
    final users = <String, Map<String, dynamic>>{
      'ana': {'barangay': 'Sambat', 'municipality': 'Tanauan'},
      'ben': {'barangay': 'Sambat', 'municipality': 'Tanauan'},
      'cora': {'barangay': 'San Gabriel', 'municipality': 'Laurel'},
      'noplace': <String, dynamic>{},
    };
    Map<String, dynamic> search(
      String userId,
      String query,
      int day, {
      int month = 10,
    }) => {'userId': userId, 'query': query, 'createdAt': at(2026, month, day)};

    final result = DashboardAnalyticsService.searchesByBuyerAreaForMonth(
      [
        search('ana', 'Tomato', 1),
        search('ana', 'tomato ', 2),
        search('ben', 'eggplant', 3),
        search('cora', 'rice', 4),
        // Not placed: no saved area, no account, another month, empty.
        search('noplace', 'tomato', 5),
        search('gone', 'tomato', 6),
        search('ana', 'tomato', 7, month: 9),
        search('ana', '  ', 8),
      ],
      users,
      year: 2026,
      month: 10,
    );

    test('counted by the searching buyer\'s saved area, busiest first', () {
      expect(result.areas.map((a) => (a.area, a.searches)), [
        ('Sambat, Tanauan', 3),
        ('San Gabriel, Laurel', 1),
      ]);
    });

    test('what was searched in each area, most searched first', () {
      expect(result.terms['Sambat, Tanauan'], [
        (term: 'tomato', searches: 2),
        (term: 'eggplant', searches: 1),
      ]);
      expect(result.terms['San Gabriel, Laurel']!.single.term, 'rice');
    });
  });
}
