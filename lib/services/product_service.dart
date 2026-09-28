import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'connectivity_service.dart';

class ProductService {
  final _products = FirebaseFirestore.instance.collection('products');

  Future<String?> addProduct({
    required String name,
    required String category,
    required double price,
    required int quantity,
    required String description,
    double? wholesalePrice,
    int wholesaleMinimumQuantity = 1,
    int retailMaximumQuantity = 1,
    List<String> imageUrls = const [],
    bool deliveryAvailable = false,
    bool pickupOnly = false,
  }) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'You are not logged in.';
      await _products.add({
        'farmerId': user.uid,
        'farmerName': user.displayName ?? 'Farmer',
        'name': name,
        'category': category,
        'price': price,
        'wholesalePrice': wholesalePrice,
        'wholesaleMinimumQuantity': wholesaleMinimumQuantity,
        'retailMaximumQuantity': retailMaximumQuantity,
        'quantity': quantity,
        'description': description,
        'imageUrls': imageUrls,
        // Keep a single 'imageUrl' (first photo) so existing screens still work.
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'deliveryAvailable': deliveryAvailable,
        'pickupOnly': pickupOnly,
        // Standardized defaults so every product doc has these fields from
        // creation instead of relying on callers to treat them as absent
        // (see docs/firestore-schema-migration.md). 'rating'/'reviewCount'
        // are kept current by ReviewService.submitReview.
        'isArchived': false,
        'isSuspended': false,
        'rating': 0.0,
        'reviewCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not save product. Please try again.';
    }
  }

  Future<String?> updateProduct({
    required String id,
    required String name,
    required String category,
    required double price,
    required int quantity,
    required String description,
    double? wholesalePrice,
    int wholesaleMinimumQuantity = 1,
    int retailMaximumQuantity = 1,
    List<String> imageUrls = const [],
    bool deliveryAvailable = false,
    bool pickupOnly = false,
  }) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _products.doc(id).update({
        'name': name,
        'category': category,
        'price': price,
        'wholesalePrice': wholesalePrice,
        'wholesaleMinimumQuantity': wholesaleMinimumQuantity,
        'retailMaximumQuantity': retailMaximumQuantity,
        'quantity': quantity,
        'description': description,
        'imageUrls': imageUrls,
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'deliveryAvailable': deliveryAvailable,
        'pickupOnly': pickupOnly,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not update product. Please try again.';
    }
  }

  Future<String?> deleteProduct(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _products.doc(id).delete();
      return null;
    } catch (e) {
      return 'Could not delete product. Please try again.';
    }
  }

  /// Pauses a listing without deleting it — hidden from the buyer
  /// marketplace, but stays in the farmer's own product list so they can
  /// restore it later (e.g. seasonal items, temporary stock-outs).
  Future<String?> archiveProduct(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _products.doc(id).update({
        'isArchived': true,
        'archivedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not archive product. Please try again.';
    }
  }

  Future<String?> unarchiveProduct(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _products.doc(id).update({
        'isArchived': false,
        'archivedAt': null,
      });
      return null;
    } catch (e) {
      return 'Could not restore product. Please try again.';
    }
  }

  /// Quick standalone quantity edit — used by the farmer's product list for
  /// restocking or correcting inventory without opening the full edit form.
  /// This manually-set value becomes the available stock for future orders,
  /// same as if it came from the full edit form.
  Future<String?> updateQuantity(String id, int quantity) async {
    if (quantity < 0) return 'Quantity cannot be negative.';
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    try {
      await _products.doc(id).update({
        'quantity': quantity,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not update quantity. Please try again.';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myProductsStream() {
    final user = FirebaseAuth.instance.currentUser;
    return _products.where('farmerId', isEqualTo: user?.uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> allProductsStream() {
    return _products.snapshots();
  }

  /// Fire-and-forget view counter — the "interaction" signal for
  /// ProductVisibilityService's ranking. Never blocks or surfaces errors to
  /// the viewer, since a missed view-count bump isn't worth interrupting
  /// anyone's browsing over.
  void logProductView(String productId) {
    _products.doc(productId).update({'viewCount': FieldValue.increment(1)}).catchError((_) {});
  }
}
