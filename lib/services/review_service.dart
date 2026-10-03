import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'connectivity_service.dart';

class ReviewService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection('productReviews');

  Stream<QuerySnapshot<Map<String, dynamic>>> productReviewsStream(String productId) {
    return _reviews.where('productId', isEqualTo: productId).snapshots();
  }

  // Same name-resolution priority used across the app post-migration:
  // Auth displayName (kept in sync by EditProfileScreen) first, then the
  // standardized 'name' field, then the legacy 'fullName' — see
  // docs/firestore-schema-migration.md.
  Future<String> _resolveBuyerName() async {
    final user = _auth.currentUser;
    if (user?.displayName?.trim().isNotEmpty == true) {
      return user!.displayName!.trim();
    }
    final uid = user?.uid;
    if (uid == null) return 'Buyer';
    final data = (await _db.collection('users').doc(uid).get()).data();
    final name = data?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final fullName = data?['fullName']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;
    return 'Buyer';
  }

  Future<String?> submitReview({
    required String orderId,
    required String productId,
    required String productName,
    required String sellerId,
    required double rating,
    required String comment,
    String? imageUrl,
  }) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      final buyerId = _auth.currentUser?.uid;
      if (buyerId == null || buyerId.isEmpty) {
        return 'Please log in again before submitting a review.';
      }

      if (rating < 0.5 || rating > 5 || rating * 2 != (rating * 2).round()) {
        return 'Choose a rating from 0.5 to 5 stars in half-star steps.';
      }
      final normalizedRating = rating;
      final trimmedComment = comment.trim();
      if (trimmedComment.isEmpty) {
        return 'Please add a short review description.';
      }

      // One review per order (doc ID == orderId), so re-submitting edits
      // the existing review instead of creating a duplicate.
      final reviewRef = _reviews.doc(orderId);
      final orderRef = _db.collection('orders').doc(orderId);

      // A review must belong to a real completed transaction: this buyer's
      // own order, completed, for this exact product. Firestore rules
      // enforce the same; checking here gives a clear message instead of a
      // permission error.
      final order = (await orderRef.get()).data();
      if (order == null || order['buyerId'] != buyerId) {
        return 'Only the buyer of this order can review it.';
      }
      if ((order['status'] ?? '').toString().toLowerCase() != 'completed') {
        return 'You can review this product once the order is completed.';
      }
      if (order['productId'] != productId || order['sellerId'] != sellerId) {
        return 'This review does not match the product in that order.';
      }

      final buyerName = await _resolveBuyerName();

      await _db.runTransaction((transaction) async {
        final existingReview = await transaction.get(reviewRef);
        final isEdit = existingReview.exists;

        transaction.set(reviewRef, {
          'orderId': orderId,
          'productId': productId,
          'productName': productName,
          'sellerId': sellerId,
          'buyerId': buyerId,
          'buyerName': buyerName,
          'rating': normalizedRating,
          'comment': trimmedComment,
          'imageUrl': imageUrl ?? '',
          // Only stamped on first submission — merge leaves it untouched
          // on a later edit of the same review.
          if (!isEdit) 'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.update(orderRef, {
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewRating': normalizedRating,
        });

        // Aggregate rating fields are maintained by a trusted server trigger.
      });

      return null;
    } on FirebaseException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        return 'Could not submit review: $msg';
      }
      return 'Could not submit review. Please try again.';
    } catch (_) {
      return 'Could not submit review. Please try again.';
    }
  }
}
