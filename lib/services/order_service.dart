import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'connectivity_service.dart';
import 'delivery_coverage.dart';
import 'market_price_helpers.dart';
import 'order_contact_service.dart';
import 'pricing_tier_service.dart';
import '../data/commodity_master_list.dart';

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
    required num unitPrice,
    required String buyerName,
    required String buyerContact,
    required String buyerAddress,
    required String deliveryMethod,
    DateTime? neededBy,
    // The buyer's general location, re-checked against the listing's
    // delivery coverage when deliveryMethod is 'delivery' (and again on
    // the server — see notifyNewOrder).
    BuyerArea? buyerArea,
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
      // Known up front so the buyer's contact number can be saved under
      // the order once it has been placed (see below).
      final orderRef = _orders.doc();

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

        // Authoritative unit: the product's own stored 'unit' field wins
        // over whatever the UI passed in (which may be derived from a
        // display string) — falls back to deriving it from the commodity/
        // name for older listings that predate the Unit field, never
        // trusting a possibly-stale caller value for what actually
        // controls inventory-deduction and order-quantity semantics.
        final realUnit =
            ((productData?['unit'] as String?)?.trim().isNotEmpty ?? false)
            ? productData!['unit'] as String
            : unitForProductName(
                (productData?['commodity'] ??
                        productData?['name'] ??
                        productName)
                    .toString(),
              );

        final available =
            (productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0;
        if (q > available) {
          throw StateError(
            'Only ${formatStock(available, realUnit)} available.',
          );
        }

        final retailPrice =
            (productData?['retailPrice'] as num?) ??
            (productData?['price'] as num?) ??
            unitPrice;
        final wholesaleEnabled =
            productData != null &&
            PricingTierService.wholesaleAvailable(productData);
        final wholesalePrice = productData?['wholesalePrice'] as num?;
        final wholesaleMinimum =
            productData?['wholesaleMinimumQuantity'] as num?;
        final quote = PricingTierService.quote(
          quantity: q,
          retailPrice: retailPrice,
          wholesaleEnabled: wholesaleEnabled,
          wholesalePrice: wholesalePrice,
          wholesaleMinimumQuantity: wholesaleMinimum,
        );
        final price = quote.unitPrice;
        final total = quote.subtotal;

        // Fulfillment, against the listing as it is now. 'total' stays the
        // product subtotal (revenue analytics read it); the delivery fee and
        // the amount including it are stored separately.
        final fulfillment = <String, dynamic>{};
        if (deliveryMethod == 'delivery') {
          if (productData?['deliveryAvailable'] != true) {
            throw StateError('Delivery is no longer offered for this product.');
          }
          final coverage = DeliveryCoverage.fromProduct(productData!);
          final reach = buyerArea == null
              ? DeliveryReach.unknownLocation
              : coverage.reach(buyerArea);
          if (reach != DeliveryReach.covered) {
            throw StateError(
              'Delivery no longer covers your area. Choose pick-up or '
              'message the farmer to arrange delivery.',
            );
          }
          final feeKnown = coverage.feeKnown;
          fulfillment.addAll({
            'deliveryArrangement': 'standard',
            'deliveryFeeType': feeKnown ? 'fixed' : 'arranged',
            'deliveryFee': feeKnown ? coverage.fee : null,
            'grandTotal': feeKnown ? total + coverage.fee! : null,
          });
        } else if (deliveryMethod == 'pickup') {
          if (productData?['pickupOnly'] != true) {
            throw StateError('Pick-up is no longer offered for this product.');
          }
          fulfillment['grandTotal'] = total;
        }

        // The listing's own category; for an older listing saved without
        // one, the category of the commodity it names. Never guessed.
        final frozenCommodity = (productData?['commodity'] ?? '')
            .toString()
            .trim();
        final listedCategory = (productData?['category'] ?? '')
            .toString()
            .trim();
        final frozenCategory = listedCategory.isNotEmpty
            ? listedCategory
            : categoryOfCommodity(frozenCommodity);

        transaction.update(productRef, {
          'quantity': available - q,
          'lastOrderId': orderRef.id,
        });
        transaction.set(orderRef, {
          'sellerId': sellerId,
          'sellerName': sellerName,
          'buyerId': buyerId,
          'buyerName': buyerName,
          // The contact number is deliberately not on this document: the
          // farmer can read an order from the moment it is placed, and
          // the number is only for an order they have confirmed. It goes
          // in orders/{id}/private/buyer — see OrderContactService.
          'buyerAddress': buyerAddress,
          // The buyer's general area as it was at checkout — barangay and
          // city, never a pin — so demand analytics keep placing this
          // purchase where it was made if the buyer later moves.
          if (buyerArea != null && buyerArea.isKnown) ...{
            'buyerBarangay': buyerArea.barangay.trim(),
            'buyerMunicipality': buyerArea.city.trim(),
            'buyerProvince': buyerArea.province.trim(),
          },
          'productId': productId,
          'productName': productName,
          // Frozen from the product doc read above (same reasoning as
          // productName/imageUrl), so the admin "Sales by Category" chart
          // still has it after the listing is edited or deleted.
          'category': frozenCategory,
          if (frozenCommodity.isNotEmpty) 'commodity': frozenCommodity,
          // Livestock: sold live or slaughtered, as listed when ordered.
          'sellingOption': ?sellingOptionOf(productData)?.value,
          'imageUrl': imageUrl,
          'quantity': q,
          'unit': realUnit,
          'quantityLabel': formatStock(q, realUnit),
          'pricingType': quote.pricingType,
          'pricePerUnit': price,
          // Keep unitPrice for backward compatibility with existing analytics/screens.
          'unitPrice': price,
          'subtotal': total,
          'total': total,
          'deliveryMethod': deliveryMethod,
          ...fulfillment,
          // The buyer's preferred date — a request for the farmer to
          // consider, never a deadline that fails the order. 'neededBy'
          // is the same value under its older name.
          if (neededBy != null) ...{
            'requestedFulfillmentDate': Timestamp.fromDate(neededBy),
            'neededBy': Timestamp.fromDate(neededBy),
          },
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      // The order stands whether or not this succeeds.
      await OrderContactService.instance.saveBuyerContact(
        orderRef.id,
        buyerContact,
      );
      return null;
    } on StateError catch (e) {
      // Our own checks above (stock, listing, fulfillment) — already
      // written for the buyer.
      return e.message;
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
  /// Buyer: "Order Received" on a shipped / ready-for-pick-up order —
  /// completes it (the receipt is issued as when the farmer completes it).
  Future<String?> confirmReceived(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Please log in again.';
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = _orders.doc(id);
        final snapshot = await transaction.get(orderRef);
        final data = snapshot.data();
        if (data == null) throw StateError('This order no longer exists.');
        if (data['buyerId'] != uid) {
          throw StateError('Only the buyer of this order can confirm it.');
        }
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'completed') return; // the farmer just did it
        if (status != 'shipped') {
          throw StateError('This order has not been sent yet.');
        }
        transaction.update(orderRef, {
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
          'completedAt': FieldValue.serverTimestamp(),
          'completedBy': 'buyer',
        });
      });
      return null;
    } on StateError catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not confirm the order. Please try again.';
    }
  }

  Future<String?> updateStatus(String id, String status) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;

    const allowedTransitions = <String, Set<String>>{
      'pending': {'confirmed'},
      'confirmed': {'shipped'},
      'shipped': {'completed'},
    };

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final orderRef = _orders.doc(id);
        final snapshot = await transaction.get(orderRef);
        if (!snapshot.exists) {
          throw StateError('This order no longer exists.');
        }

        final data = snapshot.data()!;
        final current = (data['status'] ?? 'pending').toString().toLowerCase();
        final next = status.toLowerCase();
        final allowed = allowedTransitions[current] ?? const <String>{};

        if (!allowed.contains(next)) {
          throw StateError('Order cannot move from $current to $next.');
        }

        transaction.update(orderRef, {
          'status': next,
          'updatedAt': FieldValue.serverTimestamp(),
          if (next == 'completed') 'completedAt': FieldValue.serverTimestamp(),
        });
      });
      // Confirming is what lets the two sides see each other's number for
      // this order; the farmer's comes from their profile.
      if (status.toLowerCase() == 'confirmed') {
        await OrderContactService.instance.shareFarmerContact(id);
      }
      return null;
    } on StateError catch (e) {
      return e.message;
    } catch (_) {
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
          final productRef = FirebaseFirestore.instance
              .collection('products')
              .doc(productId);
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

  // ---- Delay / reschedule ----
  // All three keep the same order: same id, same reserved stock, same
  // prices. Nothing is re-ordered and no stock is deducted again. Firestore
  // rules allow each only to the right person, in the right state, touching
  // only these fields.

  /// Farmer: report a delay on a confirmed order and propose a new date.
  ///
  /// [otherReason]: the farmer's own words when [reason] is 'other' (at most
  /// 100 characters); stored only then.
  Future<String?> reportDelay({
    required String id,
    required String reason,
    required DateTime proposedDate,
    String note = '',
    String otherReason = '',
  }) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    final other = otherReason.trim();
    if (reason == 'other' && other.isEmpty) {
      return 'Please say what is causing the delay.';
    }
    try {
      await _orders.doc(id).update({
        'delay': {
          'reason': reason,
          if (reason == 'other') 'otherReason': other,
          'note': note.trim(),
          'proposedDate': Timestamp.fromDate(proposedDate),
          'reportedAt': FieldValue.serverTimestamp(),
          'status': 'proposed',
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'Could not report the delay. Please try again.';
    }
  }

  /// Buyer: accept the date the farmer proposed. It becomes the order's
  /// confirmed fulfillment date.
  Future<String?> acceptProposedDate(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final ref = _orders.doc(id);
        final data = (await transaction.get(ref)).data();
        final delay = data?['delay'];
        if (data == null ||
            data['status'] != 'confirmed' ||
            delay is! Map ||
            delay['status'] != 'proposed' ||
            delay['proposedDate'] is! Timestamp) {
          throw StateError('There is no proposed date to accept any more.');
        }
        transaction.update(ref, {
          'delay': {...delay, 'status': 'accepted'},
          'confirmedFulfillmentDate': delay['proposedDate'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return null;
    } on StateError catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not accept the new date. Please try again.';
    }
  }

  /// Buyer: cancel an order whose new date they do not want. The reserved
  /// quantity is given back to the farmer's listing by the
  /// handleOrderReschedule Cloud Function (a buyer cannot write to a
  /// product's stock).
  Future<String?> cancelDelayedOrder(String id) async {
    final offlineError = await requireOnlineOrError();
    if (offlineError != null) return offlineError;
    try {
      await _orders.doc(id).update({
        'status': 'cancelled',
        'cancelReason': 'delay',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'Could not cancel the order. Please try again.';
    }
  }
}
