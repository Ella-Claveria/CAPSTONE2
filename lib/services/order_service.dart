import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'connectivity_service.dart';

class OrderService {
  final _orders = FirebaseFirestore.instance.collection('orders');

  // All orders where the logged-in farmer is the seller.
  Stream<QuerySnapshot<Map<String, dynamic>>> farmerOrdersStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _orders.where('sellerId', isEqualTo: uid).snapshots();
  }

  // All orders created by the logged-in buyer.
  Stream<QuerySnapshot<Map<String, dynamic>>> buyerOrdersStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _orders.where('buyerId', isEqualTo: uid).snapshots();
  }

  // Creates one order document that both buyer and farmer screens read.
  Future<String?> createOrder({
    required String sellerId,
    required String sellerName,
    required String productId,
    required String productName,
    required String imageUrl,
    required num quantity,
    required String unit,
    required num unitPrice,
    required String buyerName,
    required String buyerContact,
    required String buyerAddress,
    required String deliveryMethod,
  }) async {
    // An order must never be silently queued for later — if it can't be
    // confirmed against live Firestore data right now, it doesn't happen.
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      final buyerId = FirebaseAuth.instance.currentUser?.uid;
      if (buyerId == null || buyerId.isEmpty) {
        return 'Please log in again before placing an order.';
      }

      final q = quantity <= 0 ? 1 : quantity;
      final price = unitPrice < 0 ? 0 : unitPrice;
      final total = q * price;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final productRef = FirebaseFirestore.instance
            .collection('products')
            .doc(productId);
        final productSnapshot = await transaction.get(productRef);
        if (!productSnapshot.exists) {
          throw StateError('Product is no longer available.');
        }
        final productData = productSnapshot.data();
        if (productData?['isArchived'] == true ||
            productData?['isSuspended'] == true) {
          throw StateError('This listing is no longer available.');
        }

        final available =
            (productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0;
        if (q > available) {
          throw StateError(
            'Only ${available.toStringAsFixed(0)} item(s) are available.',
          );
        }

        final orderRef = _orders.doc();
        transaction.update(productRef, {'quantity': available - q});
        transaction.set(orderRef, {
          'sellerId': sellerId,
          'sellerName': sellerName,
          'buyerId': buyerId,
          'buyerName': buyerName,
          'buyerContact': buyerContact,
          'buyerAddress': buyerAddress,
          'productId': productId,
          'productName': productName,
          // Denormalized from the product doc we already read above (same
          // reasoning as productName/imageUrl) — lets the admin dashboard's
          // "Sales by Category" chart query orders directly instead of
          // joining every order back to its product.
          'category': productData?['category'],
          'imageUrl': imageUrl,
          'quantity': q,
          'unit': unit,
          'quantityLabel': '$q $unit',
          'unitPrice': price,
          'total': total,
          'deliveryMethod': deliveryMethod,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return null;
    } on FirebaseException catch (e) {
      final reason = (e.message ?? '').trim();
      if (reason.isNotEmpty) {
        return 'Could not place your order: $reason';
      }
      return 'Could not place your order. Please try again.';
    } catch (_) {
      return 'Could not place your order. Please try again.';
    }
  }

  // Confirm / ship / complete an order. Rejecting needs rejectOrder below
  // instead, since it also has to give the reserved stock back.
  Future<String?> updateStatus(String id, String status) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _orders.doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not update the order. Please try again.';
    }
  }

  // Rejects a pending order and returns its reserved stock to the product
  // — createOrder decrements the product's quantity immediately when the
  // order is placed (not on confirm), so rejecting without restocking
  // would leak that inventory. Both writes happen in one transaction so
  // they can never happen only one at a time.
  Future<String?> rejectOrder(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = _orders.doc(id);
        final orderSnapshot = await transaction.get(orderRef);
        if (!orderSnapshot.exists) {
          throw StateError('This order no longer exists.');
        }
        final orderData = orderSnapshot.data()!;
        if ((orderData['status'] ?? 'pending') != 'pending') {
          throw StateError('Only pending orders can be rejected.');
        }

        final productId = orderData['productId']?.toString();
        final qty = (orderData['quantity'] as num?) ?? 0;
        if (productId != null && productId.isNotEmpty) {
          final productRef =
              FirebaseFirestore.instance.collection('products').doc(productId);
          final productSnapshot = await transaction.get(productRef);
          if (productSnapshot.exists) {
            final current =
                (productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0;
            transaction.update(productRef, {'quantity': current + qty});
          }
        }

        transaction.update(orderRef, {
          'status': 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return null;
    } on StateError catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reject the order. Please try again.';
    }
  }
}
