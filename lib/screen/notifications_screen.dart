import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/message_service.dart';
import 'chat_screen.dart';
import 'message_order_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _bg = Color(0xFFF7F9F5);

  final MessageService _messageService = MessageService();

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _messageService.myConversationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _dark));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading notifications. Please try again.'));
          }

          final allDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          )
            ..sort((a, b) {
              final at = a.data()['lastMessageTime'] as Timestamp?;
              final bt = b.data()['lastMessageTime'] as Timestamp?;
              final ams = at?.millisecondsSinceEpoch ?? 0;
              final bms = bt?.millisecondsSinceEpoch ?? 0;
              return bms.compareTo(ams);
            });

          final unreadDocs = allDocs.where((doc) {
            final map = Map<String, dynamic>.from(doc.data()['unreadCount'] ?? {});
            return ((map[myUid] ?? 0) as num).toInt() > 0;
          }).toList();

          if (unreadDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No unread messages',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            itemCount: unreadDocs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final doc = unreadDocs[i];
              final data = doc.data();
              final conversationId = doc.id;
              return _unreadNotificationTile(
                context,
                conversationId,
                data,
                myUid,
              );
            },
          );
        },
      ),
    );
  }

  Widget _unreadNotificationTile(
    BuildContext context,
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
  ) {
    final participants = List<dynamic>.from(data['participants'] ?? []);
    final otherUid = participants.firstWhere(
      (id) => id != myUid,
      orElse: () => '',
    ) as String;

    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = names[otherUid]?.toString() ?? 'User';
    final lastMessage = data['lastMessage']?.toString() ?? '';
    final productName = data['productName']?.toString();
    final farmerId = data['farmerId']?.toString() ?? '';
    final isBuyerOrderConversation = farmerId.isNotEmpty && farmerId == otherUid;

    final unreadMap = Map<String, dynamic>.from(data['unreadCount'] ?? {});
    final unreadCount = ((unreadMap[myUid] ?? 0) as num).toInt();

    final timestamp = data['lastMessageTime'] as Timestamp?;
    final timeLabel = _formatTime(timestamp?.toDate());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: _accent, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isBuyerOrderConversation) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MessageOrderScreen(
                    conversationId: conversationId,
                    farmerId: otherUid,
                    productId: data['productId']?.toString() ?? '',
                    farmerName: otherName,
                    productName: productName ?? 'Product',
                    productPrice: data['productPrice']?.toString() ?? 'Price unavailable',
                    productImage: data['productImageUrl']?.toString() ?? '',
                    deliveryAvailable: data['deliveryAvailable'] == true,
                    pickupAvailable: data['pickupOnly'] == true,
                  ),
                ),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  conversationId: conversationId,
                  otherUserId: otherUid,
                  otherUserName: otherName,
                  productId: data['productId']?.toString(),
                  productName: productName,
                  productImageUrl: data['productImageUrl']?.toString(),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _accent,
                  child: Text(
                    otherName.isNotEmpty ? otherName.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              otherName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (timeLabel.isNotEmpty)
                            Text(
                              timeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      if (productName != null && productName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Re: $productName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage.isEmpty ? 'New message' : lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.month}/${date.day}';
  }
}
