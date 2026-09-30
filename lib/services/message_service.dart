import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'market_price_helpers.dart';

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

  /// Deterministic conversation id for a pair of users, independent of order.
  String conversationIdFor(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return ids.join('_');
  }

  /// Creates the conversation if it doesn't exist yet, or refreshes the
  /// product context if it does. Safe to call every time a buyer taps
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

    await chatDocRef.set({
      'participants': [currentUserId, otherUserId],
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
      'lastMessage': 'Inquiry about $productName',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUserId,
    }, SetOptions(merge: true));

    return conversationId;
  }

  Future<void> sendPricingOptions({
    required String conversationId,
    required String otherUserId,
    required num retailPrice,
    num? wholesalePrice,
    required int wholesaleMinimumQuantity,
    required int retailMaximumQuantity,
  }) async {
    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    final messageData = <String, dynamic>{
      'senderId': me.uid,
      'type': 'pricingOptions',
      'retailPrice': retailPrice,
      'wholesalePrice': wholesalePrice,
      'wholesaleMinimumQuantity': wholesaleMinimumQuantity,
      'retailMaximumQuantity': retailMaximumQuantity,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();
    batch.set(msgRef, messageData);
    batch.update(convRef, {
      'lastMessage': 'Pricing options sent',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
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
        .snapshots();
  }

  /// Real-time stream of conversations for the current user.
  Stream<QuerySnapshot<Map<String, dynamic>>> myConversationsStream() {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: currentUserId)
        .snapshots();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String otherUserId,
    String? text,
    String? imageUrl,
  }) async {
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

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

    batch.set(msgRef, messageData);
    batch.update(convRef, {
      'lastMessage': trimmed.isNotEmpty ? trimmed : 'Photo',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me.uid,
      'unreadCount.$otherUserId': FieldValue.increment(1),
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
    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

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
    });
    await batch.commit();
  }

  Future<void> sendImageMessage({
    required String conversationId,
    required String otherUserId,
    required String imageUrl,
    String? text,
  }) async {
    final caption = text?.trim() ?? '';
    if (imageUrl.isEmpty && caption.isEmpty) return;

    final me = _auth.currentUser!;
    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();

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
    });
    await batch.commit();
  }

  /// Call when the user opens a conversation, to zero out their unread badge.
  Future<void> markConversationRead(String conversationId) async {
    await _conversations.doc(conversationId).update({
      'unreadCount.$currentUid': 0,
    });
  }

  String otherParticipant(List<dynamic> participants) {
    return participants.firstWhere((id) => id != currentUid) as String;
  }
}
