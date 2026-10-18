import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'market_price_helpers.dart';
import 'connectivity_service.dart';

/// Handles chat conversations and messages between farmers and buyers.
/// FCM token registration/cleanup lives in PushNotificationService (see
/// AuthService.signOut for cleanup, AppRouter/notification_permission_prompt
/// for registration) — not duplicated here.
///
/// Firestore layout:
///   conversations/{conversationId}
///     participants: [uidA, uidB]
///     participantNames: { uid: name }
///     lastMessage, lastMessageTime, lastSenderId
///     unreadCount: { uid: count }
///     productId, productName   (context of the item that started the chat)
///     conversations/{conversationId}/messages/{messageId}
///       senderId, text, createdAt
class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  String get currentUid => _auth.currentUser!.uid;

  Future<void> _requireOnline() async {
    final error = await requireOnlineOrError();
    if (error != null) throw StateError(error);
  }

  /// Deterministic conversation id for a pair of users, independent of order.
  String conversationIdFor(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return ids.join('_');
  }

  /// Prepares the conversation with a farmer about a product: refreshes the
  /// product context of an existing thread, or — if the two have never
  /// exchanged anything — holds it as a draft that is only written when a
  /// first message is sent. Safe to call every time a buyer taps
  /// "Message Seller" on a product.
  Future<String> startOrGetConversation({
    required String otherUserId,
    required String otherUserName,
    required String productId,
    required String productName,
    required String productImageUrl,
    num? retailPrice,
    num? wholesalePrice,
    int wholesaleMinimumQuantity = 1,
    int retailMaximumQuantity =
        1, // Legacy metadata retained for older conversations.
    String unit = 'kg',
    bool deliveryAvailable = false,
    bool pickupOnly = false,
  }) async {
    await _requireOnline();
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final currentUser = FirebaseAuth.instance.currentUser!;
    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();
    final userData = userSnapshot.data();
    final currentUserName = currentUser.displayName?.trim().isNotEmpty == true
        ? currentUser.displayName!.trim()
        : (userData?['name']?.toString().trim().isNotEmpty == true
              ? userData!['name'].toString().trim()
              : userData?['fullName']?.toString().trim().isNotEmpty == true
              ? userData!['fullName'].toString().trim()
              : 'Buyer');

    // Consistent conversation ID format
    // Use your existing helper method to ensure consistency
    final conversationId = conversationIdFor(currentUserId, otherUserId);

    final chatDocRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId);

    // Product context and names — no lastMessage: nothing has been said.
    final context = <String, dynamic>{
      'participantNames': {
        currentUserId: currentUserName,
        otherUserId: otherUserName,
      },
      'farmerId': otherUserId,
      'farmerName': otherUserName,
      // Standardized product-context fields — see
      // docs/firestore-schema-migration.md. 'farmerImage' below is kept
      // (unused/deprecated) only so older reads of it aren't broken; new
      // reads should use 'productImageUrl'.
      'productId': productId,
      'productName': productName,
      'productImageUrl': productImageUrl,
      'productPrice': formatPriceWithUnit(retailPrice ?? 0, unit),
      'unit': unit,
      'deliveryAvailable': deliveryAvailable,
      'pickupOnly': pickupOnly,
      'farmerImage': productImageUrl,
      'retailPrice': retailPrice,
      'wholesalePrice': wholesalePrice,
      'wholesaleMinimumQuantity': wholesaleMinimumQuantity,
      'retailMaximumQuantity': retailMaximumQuantity,
    };

    if ((await chatDocRef.get()).exists) {
      // An existing thread: just bring its product context up to date. Its
      // last message, time and unread counts are left exactly as they are
      // — opening the chat is not a message.
      _drafts.remove(conversationId);
      await chatDocRef.set(context, SetOptions(merge: true));
    } else {
      // No thread yet: nothing is written. It is created by the first
      // message actually sent (see _ensureConversation); leaving the chat
      // without sending leaves no trace.
      _drafts[conversationId] = {
        'participants': [currentUserId, otherUserId],
        ...context,
      };
    }

    return conversationId;
  }

  /// The one conversation between an order's farmer and buyer. If the two
  /// have never chatted it is held as a draft and created by the first
  /// message sent (see _ensureConversation) — only
  /// then. Unlike [startOrGetConversation] it can
  /// be called from either side and never overwrites an existing
  /// conversation's product context. Used by the Orders screens.
  Future<String> ensureOrderConversation({
    required String sellerId,
    required String sellerName,
    required String buyerId,
    required String buyerName,
    required String productId,
    required String productName,
    required String productImageUrl,
  }) async {
    await _requireOnline();
    final conversationId = conversationIdFor(sellerId, buyerId);
    final ref = _conversations.doc(conversationId);
    if ((await ref.get()).exists) {
      _drafts.remove(conversationId);
      return conversationId;
    }

    // Not written yet — created by the first message actually sent.
    _drafts[conversationId] = {
      'participants': [buyerId, sellerId],
      'participantNames': {buyerId: buyerName, sellerId: sellerName},
      'farmerId': sellerId,
      'farmerName': sellerName,
      'productId': productId,
      'productName': productName,
      'productImageUrl': productImageUrl,
      'farmerImage': productImageUrl,
    };
    return conversationId;
  }

  /// Puts the receipt card of a completed order into the conversation, if
  /// it isn't there already. The issueOrderReceipt Cloud Function normally
  /// does this the moment the order completes; this is the farmer's manual
  /// "send receipt" for when it hasn't. One card per order (the message id
  /// is derived from the order id), and Firestore rules only accept it from
  /// the seller of a completed order. The card carries no editable values —
  /// the receipt itself is always opened from the transaction record.
  Future<void> sendReceiptMessage({
    required String conversationId,
    required String buyerId,
    required String orderId,
    required String orderDisplayId,
    required String receiptNumber,
    required String productId,
    required String productName,
    required num subtotal,
    required num? total,
  }) async {
    await _requireOnline();
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc('receipt_$orderId');
    if ((await msgRef.get()).exists) return;

    await _ensureConversation(conversationId);
    final batch = _firestore.batch();
    batch.set(msgRef, {
      'senderId': currentUid,
      'type': 'receipt',
      'orderId': orderId,
      'orderDisplayId': orderDisplayId,
      'receiptNumber': receiptNumber,
      'productId': productId,
      'productName': productName,
      'subtotal': subtotal,
      'total': total,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(convRef, {
      'lastMessage': 'Transaction receipt · Order #$orderDisplayId',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUid,
      'unreadCount.$buyerId': FieldValue.increment(1),
      'hasMessages': true,
    });
    await batch.commit();
  }

  /// Sends an order-options card (Retail, plus Wholesale when the listing
  /// offers it) for one product, at the prices current when sent. The
  /// buyer's choice is re-checked against the listing before ordering.
  Future<void> sendPricingOptions({
    required String conversationId,
    required String otherUserId,
    required num retailPrice,
    num? wholesalePrice,
    required num wholesaleMinimumQuantity,
    int retailMaximumQuantity = 1, // Legacy field, kept for older readers.
    String? productId,
    String? productName,
    String? unit,
    bool wholesaleEnabled = true,
    // Delivery/pick-up availability as shown to the buyer when sent, e.g.
    // "Delivery: Within Laurel · ₱50.00" (see ChatProduct.deliveryLabel).
    bool? deliveryAvailable,
    bool? pickupAvailable,
    String? deliveryLabel,
    String? pickupLabel,
  }) async {
    await _requireOnline();
    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    final messageData = <String, dynamic>{
      'senderId': me.uid,
      'type': 'pricingOptions',
      'productId': ?productId,
      'productName': ?productName,
      'unit': ?unit,
      'retailPrice': retailPrice,
      'wholesaleEnabled': wholesaleEnabled,
      'wholesalePrice': wholesaleEnabled ? wholesalePrice : null,
      'wholesaleMinimumQuantity': wholesaleMinimumQuantity,
      'retailMaximumQuantity': retailMaximumQuantity,
      'deliveryAvailable': ?deliveryAvailable,
      'pickupAvailable': ?pickupAvailable,
      'deliveryLabel': ?deliveryLabel,
      'pickupLabel': ?pickupLabel,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _ensureConversation(conversationId);
    final batch = _firestore.batch();
    batch.set(msgRef, messageData);
    batch.update(convRef, {
      'lastMessage': productName == null
          ? 'Order options sent'
          : 'Order options for $productName',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
      'hasMessages': true,
    });
    await batch.commit();
  }

  /// Real-time stream of messages in a conversation, newest first
  /// (so it can be fed directly into a reversed ListView).
  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String conversationId,
  ) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> typingStream(
    String conversationId,
    String uid,
  ) => _conversations
      .doc(conversationId)
      .collection('typing')
      .doc(uid)
      .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> readReceiptStream(
    String conversationId,
    String uid,
  ) => _conversations
      .doc(conversationId)
      .collection('reads')
      .doc(uid)
      .snapshots();

  Future<void> setTyping(String conversationId, bool isTyping) async {
    await _conversations
        .doc(conversationId)
        .collection('typing')
        .doc(currentUid)
        .set({'isTyping': isTyping, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> toggleLike(String conversationId, String messageId) async {
    await _requireOnline();
    final ref = _conversations
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final likes = Map<String, dynamic>.from(snapshot.data()?['likes'] ?? {});
      if (likes[currentUid] == true) {
        transaction.update(ref, {'likes.$currentUid': FieldValue.delete()});
      } else {
        transaction.update(ref, {'likes.$currentUid': true});
      }
    });
  }

  /// Real-time stream of conversations for the current user.
  Stream<QuerySnapshot<Map<String, dynamic>>> myConversationsStream() {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: currentUserId)
        .snapshots();
  }

  /// The buyer's one-tap request for a livestock listing's health
  /// certificate (the suggestion over the chat's message box). Saved as
  /// 'kind' on an ordinary text message, so it reads like any other.
  static const String certificateRequestKind = 'certificateRequest';
  static const String certificateRequestText =
      "Can I see the animal's health certificate?";

  Future<void> sendMessage({
    required String conversationId,
    required String otherUserId,
    String? text,
    String? imageUrl,
    Map<String, dynamic>? replyTo,
    // What kind of message this is beyond its text, e.g.
    // [certificateRequestKind]. Left out for an ordinary message.
    String? kind,
  }) async {
    await _requireOnline();
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

    await _ensureConversation(conversationId);
    final batch = _firestore.batch();
    final messageData = {
      'senderId': FirebaseAuth.instance.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (trimmed.isNotEmpty) {
      messageData['text'] = trimmed;
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      messageData['imageUrl'] = imageUrl;
    }
    if (replyTo != null) {
      messageData['replyTo'] = replyTo;
    }
    if (kind != null) messageData['kind'] = kind;

    batch.set(msgRef, messageData);
    batch.update(convRef, {
      'lastMessage': trimmed.isNotEmpty ? trimmed : 'Photo',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
      'hasMessages': true,
    });
    await batch.commit();
  }

  /// Shares the sender's current coordinates as a one-off message — used
  /// on demand from either side of a conversation (e.g. to coordinate a
  /// pickup/delivery point), distinct from a farmer's static registered
  /// farm location.
  Future<void> sendLocationMessage({
    required String conversationId,
    required String otherUserId,
    required double latitude,
    required double longitude,
  }) async {
    await _requireOnline();
    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

    await _ensureConversation(conversationId);
    final batch = _firestore.batch();
    batch.set(msgRef, {
      'senderId': me.uid,
      'type': 'location',
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(convRef, {
      'lastMessage': 'Shared their location',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
      'hasMessages': true,
    });
    await batch.commit();
  }

  Future<void> sendImageMessage({
    required String conversationId,
    required String otherUserId,
    required String imageUrl,
    String? text,
  }) async {
    await _requireOnline();
    final caption = text?.trim() ?? '';
    if (imageUrl.isEmpty && caption.isEmpty) return;

    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

    await _ensureConversation(conversationId);
    final batch = _firestore.batch();
    final messageData = {
      'senderId': me.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'imageUrl': imageUrl,
    };
    if (caption.isNotEmpty) {
      messageData['text'] = caption;
    }

    batch.set(msgRef, messageData);
    batch.update(convRef, {
      'lastMessage': caption.isNotEmpty ? caption : 'Photo',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
      'hasMessages': true,
    });
    await batch.commit();
  }

  /// Call when the user opens a conversation, to zero out their unread badge.
  Future<void> markConversationRead(String conversationId) async {
    // A chat that is still only a draft has no thread to mark, and opening
    // it must not create one.
    if (_drafts.containsKey(conversationId)) return;
    final conversation = _conversations.doc(conversationId);
    final batch = _firestore.batch();
    batch.update(conversation, {'unreadCount.$currentUid': 0});
    batch.set(conversation.collection('reads').doc(currentUid), {
      'lastReadAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (_) {
      // No such thread (nothing sent yet), or offline — nothing to mark.
    }
  }

  // ---- Draft conversations ----
  // Tapping "Message" (or opening a chat from an order) for a pair that has
  // never exchanged anything does not write a conversation: its details are
  // kept here, in memory, and the document is created by the first message
  // that is really sent — text, photo, location, order options or receipt.
  // Leaving without sending leaves nothing in Firestore and nothing in
  // either person's Messages list.
  static final Map<String, Map<String, dynamic>> _drafts = {};

  Future<void> _ensureConversation(String conversationId) async {
    final draft = _drafts[conversationId];
    if (draft == null) return;
    await _conversations
        .doc(conversationId)
        .set(draft, SetOptions(merge: true));
    _drafts.remove(conversationId);
  }

  // ---- Which conversations belong in the Messages list ----
  // Only ones with real content. Every send marks the conversation
  // `hasMessages: true`. Conversations from before that flag existed are
  // judged by their last message: a real one counts; the old placeholder
  // text written just for opening a chat ("Inquiry about …", "Order for
  // …") does not prove anything, so those are checked once for an actual
  // message (and marked, if they have one).
  static final Map<String, bool> _checkedActivity = {};
  static final Set<String> _checkingActivity = {};

  static bool _isPlaceholderPreview(String lastMessage) =>
      lastMessage.isEmpty ||
      lastMessage.startsWith('Inquiry about ') ||
      lastMessage.startsWith('Order for ');

  /// True if [data] (conversation [conversationId]) has real message
  /// activity and should be listed; false if it is an empty shell. Returns
  /// false while an old conversation is still being checked, then calls
  /// [onResolved] so the list can rebuild.
  bool hasMessageActivity(
    String conversationId,
    Map<String, dynamic> data, {
    void Function()? onResolved,
  }) {
    if (data['hasMessages'] == true) return true;
    if (!_isPlaceholderPreview((data['lastMessage'] ?? '').toString())) {
      return true;
    }
    final checked = _checkedActivity[conversationId];
    if (checked != null) return checked;

    if (_checkingActivity.add(conversationId)) {
      final ref = _conversations.doc(conversationId);
      ref
          .collection('messages')
          .limit(1)
          .get()
          .then((snap) {
            final has = snap.docs.isNotEmpty;
            _checkedActivity[conversationId] = has;
            if (has) {
              // So it never needs checking again, on any device.
              ref.update({'hasMessages': true}).catchError((_) {});
            }
          })
          .catchError((_) {
            // Could not check (offline): leave it hidden for now and try
            // again the next time the list is opened.
          })
          .whenComplete(() {
            _checkingActivity.remove(conversationId);
            onResolved?.call();
          });
    }
    return false;
  }

  String otherParticipant(List<dynamic> participants) {
    return participants.firstWhere((id) => id != currentUid) as String;
  }
}
