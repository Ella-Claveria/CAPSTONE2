import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/message_service.dart';
import 'chat_screen.dart';
import 'message_order_screen.dart';

/// The "Messages" tab: a live list of the current user's conversations,
/// sorted by most recent activity — same idea as a Messenger inbox.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  final MessageService _messageService = MessageService();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        _searchBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _messageService.myConversationsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: _dark),
                );
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Something went wrong loading messages.'),
                );
              }

              var docs =
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                    snapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                  )..sort((a, b) {
                    final at = a.data()['lastMessageTime'] as Timestamp?;
                    final bt = b.data()['lastMessageTime'] as Timestamp?;
                    final ams = at?.millisecondsSinceEpoch ?? 0;
                    final bms = bt?.millisecondsSinceEpoch ?? 0;
                    return bms.compareTo(ams);
                  });

              if (_query.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data();
                  final participants = List<dynamic>.from(
                    data['participants'] ?? [],
                  );
                  final otherUid = participants.firstWhere(
                    (id) => id != myUid,
                    orElse: () => '',
                  );
                  final names = Map<String, dynamic>.from(
                    data['participantNames'] ?? {},
                  );
                  final otherName = (names[otherUid]?.toString() ?? '')
                      .toLowerCase();
                  final lastMessage = (data['lastMessage']?.toString() ?? '')
                      .toLowerCase();
                  final productName = (data['productName']?.toString() ?? '')
                      .toLowerCase();
                  return otherName.contains(_query) ||
                      lastMessage.contains(_query) ||
                      productName.contains(_query);
                }).toList();
              }

              if (docs.isEmpty) {
                return _query.isNotEmpty ? _noResultsState() : _emptyState();
              }

              return RefreshIndicator(
                color: _dark,
                onRefresh: _refreshData,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    return _conversationTile(context, doc.id, data, myUid);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search inquiries or buyers...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 22),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[500], size: 20),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _noResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 44, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No matches for "$_query"',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(
    BuildContext context,
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
  ) {
    final participants = List<dynamic>.from(data['participants'] ?? []);
    final otherUid =
        participants.firstWhere((id) => id != myUid, orElse: () => '')
            as String;

    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = names[otherUid]?.toString() ?? 'User';

    if (otherName == 'Buyer' ||
        otherName == 'User' ||
        otherName.trim().isEmpty) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(otherUid)
            .snapshots(),
        builder: (context, snapshot) {
          final profile = snapshot.data?.data();
          // 'name' (kept fresh by EditProfileScreen) wins over 'fullName'
          // (set once at signup and never updated afterward) — see
          // docs/firestore-schema-migration.md.
          final resolvedName =
              profile?['name']?.toString().trim().isNotEmpty == true
              ? profile!['name'].toString().trim()
              : profile?['fullName']?.toString().trim().isNotEmpty == true
              ? profile!['fullName'].toString().trim()
              : otherName;
          return _conversationTileContent(
            context,
            conversationId,
            data,
            myUid,
            otherUid,
            resolvedName,
          );
        },
      );
    }

    return _conversationTileContent(
      context,
      conversationId,
      data,
      myUid,
      otherUid,
      otherName,
    );
  }

  Widget _conversationTileContent(
    BuildContext context,
    String conversationId,
    Map<String, dynamic> data,
    String? myUid,
    String otherUid,
    String otherName,
  ) {
    final lastMessage = data['lastMessage']?.toString() ?? '';
    final lastSenderId = data['lastSenderId']?.toString() ?? '';
    final productName = data['productName']?.toString();

    final unreadMap = Map<String, dynamic>.from(data['unreadCount'] ?? {});
    final unread = ((unreadMap[myUid] ?? 0) as num).toInt();

    final timestamp = data['lastMessageTime'] as Timestamp?;
    final timeLabel = _formatTime(timestamp?.toDate());

    final youSent = lastSenderId == myUid;
    final preview = lastMessage.isEmpty
        ? 'Say hello 👋'
        : '${youSent ? 'You: ' : ''}$lastMessage';

    final farmerId = data['farmerId']?.toString() ?? '';
    final isBuyerOrderConversation =
        farmerId.isNotEmpty && farmerId == otherUid;

    return InkWell(
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
                productName: data['productName']?.toString() ?? 'Product',
                productPrice:
                    data['productPrice']?.toString() ?? 'Price unavailable',
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
              isFarmer: data['farmerId']?.toString() == myUid,
              productId: data['productId']?.toString(),
              productName: productName,
              productImageUrl: data['productImageUrl']?.toString(),
              retailPrice:
                  (data['retailPrice'] as num?) ??
                  (data['productPrice'] as num?),
              wholesalePrice: data['wholesalePrice'] as num?,
              wholesaleMinimumQuantity:
                  (data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
              retailMaximumQuantity:
                  (data['retailMaximumQuantity'] as num?)?.toInt() ?? 1,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _accent,
              child: Text(
                otherName.isNotEmpty
                    ? otherName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: _dark,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: unread > 0 ? _dark : Colors.grey[500],
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
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
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread > 0
                                ? Colors.black87
                                : Colors.grey[600],
                            fontWeight: unread > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: _dark,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 20),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mail_outline, size: 54, color: _dark),
            ),
            const SizedBox(height: 20),
            const Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When a buyer messages you about a product,\nthe conversation will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && now.day == dt.day) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $period';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.month}/${dt.day}/${dt.year % 100}';
    }
  }
}
