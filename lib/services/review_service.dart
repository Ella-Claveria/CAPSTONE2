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
    required int rating,
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

      final normalizedRating = rating.clamp(1, 5);
      final trimmedComment = comment.trim();
      if (trimmedComment.isEmpty) {
        return 'Please add a short review description.';
      }

      final buyerName = await _resolveBuyerName();

      // One review per order (doc ID == orderId), so re-submitting edits
      // the existing review instead of creating a duplicate.
      final reviewRef = _reviews.doc(orderId);
      final orderRef = _db.collection('orders').doc(orderId);
      final productRef = _db.collection('products').doc(productId);

      await _db.runTransaction((transaction) async {
        final existingReview = await transaction.get(reviewRef);
        final productSnap = await transaction.get(productRef);
        final isEdit = existingReview.exists;
        final oldRating = (existingReview.data()?['rating'] as num?)?.toInt();

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

        // Keep the product's aggregate rating/reviewCount in sync — these
        // fields are displayed on the marketplace grid and product detail
        // screen but, before this fix, were never actually written by
        // anything (see docs/firestore-schema-migration.md).
        if (productSnap.exists) {
          final productData = productSnap.data() ?? const <String, dynamic>{};
          final currentAverage =
              (productData['rating'] as num?)?.toDouble() ?? 0.0;
          final currentCount = (productData['reviewCount'] as num?)?.toInt() ?? 0;

          final int newCount;
          final double newAverage;
          if (isEdit && oldRating != null) {
            newCount = currentCount == 0 ? 1 : currentCount;
            newAverage =
                (currentAverage * newCount - oldRating + normalizedRating) /
                    newCount;
          } else {
            newCount = currentCount + 1;
            newAverage =
                (currentAverage * currentCount + normalizedRating) / newCount;
          }

          transaction.update(productRef, {
            'rating': newAverage,
            'reviewCount': newCount,
          });
        }
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
