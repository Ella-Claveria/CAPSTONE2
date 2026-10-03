import 'package:flutter/material.dart';
import 'chat_screen.dart';

/// Opens the chat thread for a conversation doc. Shared by the Messages
/// list and the Messages search screen so both open a chat the same way.
Future<void> openConversation(
  BuildContext context, {
  required String conversationId,
  required Map<String, dynamic> data,
  required String? myUid,
  required String otherUid,
  required String otherName,
  String? otherPhotoUrl,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: conversationId,
        otherUserId: otherUid,
        otherUserName: otherName,
        otherUserPhotoUrl: otherPhotoUrl,
        isFarmer: data['farmerId']?.toString() == myUid,
        productId: data['productId']?.toString(),
        productName: data['productName']?.toString(),
        productImageUrl: data['productImageUrl']?.toString(),
        retailPrice:
            (data['retailPrice'] as num?) ?? (data['productPrice'] as num?),
        wholesalePrice: data['wholesalePrice'] as num?,
        wholesaleMinimumQuantity:
            (data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
        retailMaximumQuantity:
            (data['retailMaximumQuantity'] as num?)?.toInt() ?? 1,
      ),
    ),
  );
}
