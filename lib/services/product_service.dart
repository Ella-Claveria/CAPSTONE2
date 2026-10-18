import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'connectivity_service.dart';

class ProductService {
  static const String archiveBlockedByOrdersMessage =
      'This product has pending orders. Resolve them before archiving it.';

  /// Shown wherever a farmer tries to change an archived product.
  static const String archivedReadOnlyMessage =
      'Restore this product before making changes.';

  final _products = FirebaseFirestore.instance.collection('products');

  // Archived products are read-only: returns [archivedReadOnlyMessage] if
  // [id] is archived, or null if it can be changed. A failed read is left
  // for the write that follows to report.
  Future<String?> _archivedError(String id) async {
    try {
      final snap = await _products.doc(id).get();
      return snap.data()?['isArchived'] == true
          ? archivedReadOnlyMessage
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> addProduct({
    required String name,
    required String category,
    required double price,
    required num quantity,
    required String description,
    bool wholesaleEnabled = false,
    double? wholesalePrice,
    num wholesaleMinimumQuantity = 1,
    num retailMaximumQuantity = 1,
    List<String> imageUrls = const [],
    bool deliveryAvailable = false,
    bool pickupOnly = false,
    // Where and for what fee this listing delivers (DeliveryCoverage.toMap,
    // see delivery_coverage.dart). Saved only while delivery is on.
    Map<String, dynamic>? deliveryCoverage,
    // The official AgriTrade+ Commodity Master List entry this listing
    // represents (see commodity_master_list.dart), if the farmer picked
    // one — optional, and separate from 'name'/'category': it exists only
    // to drive the AI-Assisted Price Recommendation's matching, never
    // shown to buyers or used to restrict what a farmer can list.
    String? commodity,
    // The commodity's configured unit of measurement (see
    // commodity_master_list.dart's CommodityRegistry) — e.g. 'kg', 'piece',
    // 'head', 'kg liveweight'. Saved alongside the listing so every screen
    // that later displays this product's stock/price shows the same unit,
    // instead of each one re-deriving it independently.
    String? unit,
    // Livestock only: 'live' or 'slaughtered' (SellingOption.value, see
    // commodity_master_list.dart). Null for anything else.
    String? sellingOption,
    // Internal moderation flag, set only when the farmer chose to post at
    // a price far above the AI suggested range (see add_product_screen's
    // high-price warning). Never shown to buyers; exists so the Admin
    // Moderation Queue can pick out unusually high-priced listings.
    Map<String, dynamic>? priceFlag,
    // When this batch was harvested, as entered by the farmer (see
    // harvest_info.dart). Optional, and only for produce categories.
    DateTime? harvestDate,
  }) async {
    if (imageUrls.isEmpty) return 'Please add a product photo.';
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
        if (commodity != null && commodity.isNotEmpty) 'commodity': commodity,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        'sellingOption': ?sellingOption,
        'price': price,
        'retailPrice': price,
        'wholesaleEnabled': wholesaleEnabled,
        'wholesalePrice': wholesaleEnabled ? wholesalePrice : null,
        'wholesaleMinimumQuantity': wholesaleEnabled
            ? wholesaleMinimumQuantity
            : 1,
        'retailMaximumQuantity': retailMaximumQuantity,
        'quantity': quantity,
        // What Low Stock is measured against (inventory_screen.dart).
        'stockBaseline': quantity,
        if (harvestDate != null) 'harvestDate': Timestamp.fromDate(harvestDate),
        'description': description,
        'imageUrls': imageUrls,
        // Keep a single 'imageUrl' (first photo) so existing screens still work.
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'deliveryAvailable': deliveryAvailable,
        'pickupOnly': pickupOnly,
        if (deliveryAvailable && deliveryCoverage != null)
          'deliveryCoverage': deliveryCoverage,
        // Standardized defaults so every product doc has these fields from
        // creation instead of relying on callers to treat them as absent
        // (see docs/firestore-schema-migration.md). 'rating'/'reviewCount'
        // are kept current by ReviewService.submitReview.
        if (priceFlag != null)
          'priceFlag': {
            ...priceFlag,
            'flaggedAt': FieldValue.serverTimestamp(),
          },
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
    required num quantity,
    required String description,
    bool wholesaleEnabled = false,
    double? wholesalePrice,
    num wholesaleMinimumQuantity = 1,
    num retailMaximumQuantity = 1,
    List<String> imageUrls = const [],
    bool deliveryAvailable = false,
    bool pickupOnly = false,
    // See addProduct's deliveryCoverage param — removed when delivery is off.
    Map<String, dynamic>? deliveryCoverage,
    // See addProduct's commodity param — null/empty clears it (a farmer
    // can un-pick a commodity when editing).
    String? commodity,
    // See addProduct's unit param.
    String? unit,
    // See addProduct's sellingOption param — null removes it.
    String? sellingOption,
    // See addProduct's priceFlag param.
    Map<String, dynamic>? priceFlag,
    // Removes an earlier flag, so a farmer who brings the price back down
    // is no longer flagged. The field is otherwise left out of the write
    // entirely, so an ordinary edit never touches it.
    bool clearPriceFlag = false,
    // See addProduct's harvestDate param. A new batch is recorded by
    // changing this on the same listing, not by posting a new one.
    DateTime? harvestDate,
    // Removes a stored harvest date (cleared by the farmer, or the category
    // no longer has one). Otherwise the field is left out of the write, so
    // an edit that doesn't involve it never touches it.
    bool clearHarvestDate = false,
  }) async {
    if (imageUrls.isEmpty) return 'Please add a product photo.';
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    final archivedError = await _archivedError(id);
    if (archivedError != null) return archivedError;

    // A changed quantity is a restock (or a correction) by the farmer, so
    // it becomes the new Low Stock baseline; an edit that leaves the
    // quantity as it is keeps the old one.
    num? currentQuantity;
    try {
      final current = (await _products.doc(id).get()).data()?['quantity'];
      currentQuantity = current is num ? current : null;
    } catch (_) {
      currentQuantity = null;
    }

    try {
      await _products.doc(id).update({
        if (currentQuantity != quantity) 'stockBaseline': quantity,
        'name': name,
        'category': category,
        'commodity': (commodity != null && commodity.isNotEmpty)
            ? commodity
            : FieldValue.delete(),
        'unit': (unit != null && unit.isNotEmpty) ? unit : FieldValue.delete(),
        'sellingOption': sellingOption ?? FieldValue.delete(),
        'price': price,
        'retailPrice': price,
        'wholesaleEnabled': wholesaleEnabled,
        'wholesalePrice': wholesaleEnabled ? wholesalePrice : null,
        'wholesaleMinimumQuantity': wholesaleEnabled
            ? wholesaleMinimumQuantity
            : 1,
        'retailMaximumQuantity': retailMaximumQuantity,
        'quantity': quantity,
        if (harvestDate != null)
          'harvestDate': Timestamp.fromDate(harvestDate)
        else if (clearHarvestDate)
          'harvestDate': FieldValue.delete(),
        'description': description,
        'imageUrls': imageUrls,
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
        'deliveryAvailable': deliveryAvailable,
        'pickupOnly': pickupOnly,
        'deliveryCoverage': deliveryAvailable && deliveryCoverage != null
            ? deliveryCoverage
            : FieldValue.delete(),
        if (priceFlag != null)
          'priceFlag': {...priceFlag, 'flaggedAt': FieldValue.serverTimestamp()}
        else if (clearPriceFlag)
          'priceFlag': FieldValue.delete(),
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
      final farmerId = FirebaseAuth.instance.currentUser?.uid;
      if (farmerId == null || farmerId.isEmpty) {
        return 'Please log in again before archiving this product.';
      }

      final orders = await FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: farmerId)
          .get(const GetOptions(source: Source.server));
      final hasUnfulfilledOrders = orders.docs.any((order) {
        final data = order.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        return data['productId'] == id &&
            const {'pending', 'confirmed', 'shipped'}.contains(status);
      });
      if (hasUnfulfilledOrders) {
        return archiveBlockedByOrdersMessage;
      }

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
      await _products.doc(id).update({'isArchived': false, 'archivedAt': null});
      return null;
    } catch (e) {
      return 'Could not restore product. Please try again.';
    }
  }

  /// Quick standalone quantity edit — used by the farmer's product list for
  /// restocking or correcting inventory without opening the full edit form.
  /// This manually-set value becomes the available stock for future orders,
  /// same as if it came from the full edit form.
  Future<String?> updateQuantity(String id, num quantity) async {
    if (quantity < 0) return 'Quantity cannot be negative.';
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    final archivedError = await _archivedError(id);
    if (archivedError != null) return archivedError;

    try {
      await _products.doc(id).update({
        'quantity': quantity,
        // The farmer set it: Low Stock is now measured from here.
        'stockBaseline': quantity,
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
    _products
        .doc(productId)
        .update({'viewCount': FieldValue.increment(1)})
        .catchError((_) {});
  }
}
