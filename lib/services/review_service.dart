import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection('productReviews');

  Stream<QuerySnapshot<Map<String, dynamic>>> productReviewsStream(String productId) {
    return _reviews.where('productId', isEqualTo: productId).snapshots();
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

      // One review per order.
      final reviewId = orderId;
      await _reviews.doc(reviewId).set({
        'orderId': orderId,
        'productId': productId,
        'productName': productName,
        'sellerId': sellerId,
        'buyerId': buyerId,
        'buyerName': 'Buyer',
        'rating': normalizedRating,
        'comment': trimmedComment,
        'imageUrl': imageUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Mark order reviewed so UI can disable duplicate submissions.
      await _db.collection('orders').doc(orderId).update({
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewRating': normalizedRating,
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
