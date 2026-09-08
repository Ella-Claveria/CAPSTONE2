import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Stream<QuerySnapshot<Map<String, dynamic>>> myProductsStream() {
    final user = FirebaseAuth.instance.currentUser;
    return _products.where('farmerId', isEqualTo: user?.uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> allProductsStream() {
    return _products.snapshots();
  }
}
