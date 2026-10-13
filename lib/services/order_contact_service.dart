import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ph_mobile.dart';

/// The mobile numbers a buyer and a farmer may use to reach each other
/// about one order.
///
/// They are kept off the order document itself, in two private documents
/// under it, so firestore.rules can decide who reads which and when:
///
///   orders/{orderId}/private/buyer    { contact, updatedAt }
///   orders/{orderId}/private/farmer   { contact, updatedAt }
///
/// Each side can always read its own. The other side can read it only
/// while the order is confirmed or on its way ([isShared]) — not while it
/// is still pending, and not once it is completed, rejected or cancelled.
/// In-app Messages stays the main way to talk; these numbers are a
/// fallback for an order that is actually going ahead.
///
/// Orders placed before this existed carry the buyer's number on the order
/// document itself (`buyerContact`); [otherPartyContact] falls back to it.
class OrderContactService {
  OrderContactService._();
  static final OrderContactService instance = OrderContactService._();

  static const String buyerSide = 'buyer';
  static const String farmerSide = 'farmer';

  /// Whether an order in [status] is one whose two sides may see each
  /// other's number. Mirrors contactShared() in firestore.rules.
  static bool isShared(String status) =>
      status == 'confirmed' || status == 'shipped';

  /// A number as it is stored and shown, or '' if [raw] is not a valid
  /// Philippine mobile number in any of the forms the app has ever saved.
  static String normalized(String? raw) {
    final digits = phMobileLocalDigits(raw);
    return isValidPhMobile(digits) ? phMobileE164(digits) : '';
  }

  DocumentReference<Map<String, dynamic>> _doc(String orderId, String side) =>
      FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('private')
          .doc(side);

  /// Saves the number the buyer confirmed on Place Order, for that order
  /// only. The order itself is already placed by the time this runs, so a
  /// failure here never undoes it — the two sides can still use Messages.
  Future<void> saveBuyerContact(String orderId, String contact) =>
      _save(orderId, buyerSide, contact);

  /// Called when the farmer confirms an order: puts the number from the
  /// farmer's own profile on that order for the buyer. Does nothing if the
  /// profile has no valid number.
  Future<void> shareFarmerContact(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = profile.data();
      await _save(
        orderId,
        farmerSide,
        (data?['mobileNumber'] ?? data?['phone'])?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('[OrderContact] farmer number not shared: $e');
    }
  }

  Future<void> _save(String orderId, String side, String contact) async {
    final value = normalized(contact);
    if (value.isEmpty) return;
    try {
      await _doc(
        orderId,
        side,
      ).set({'contact': value, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      // Never the number itself — only that it could not be saved.
      debugPrint('[OrderContact] $side number not saved: $e');
    }
  }

  /// The other side's number for this order, or '' if there is none or it
  /// may not be read yet. [viewerIsFarmer] says which side is asking.
  Future<String> otherPartyContact({
    required String orderId,
    required bool viewerIsFarmer,
    String? legacyBuyerContact,
  }) async {
    try {
      final snap = await _doc(
        orderId,
        viewerIsFarmer ? buyerSide : farmerSide,
      ).get();
      final contact = normalized(snap.data()?['contact']?.toString());
      if (contact.isNotEmpty) return contact;
    } catch (_) {
      // Not readable (yet) — fall through.
    }
    return viewerIsFarmer ? normalized(legacyBuyerContact) : '';
  }
}
