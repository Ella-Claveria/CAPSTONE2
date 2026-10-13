import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';
import '../services/conversation_prefs_service.dart';
import '../services/message_service.dart';
import 'buyer_marketplace_screen.dart';
import 'chat_attachments.dart';
import 'chat_product_context.dart';
import 'conversation_info_screen.dart';
import 'conversation_tools_screens.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/open_in_maps_button.dart';
import '../widgets/profile_avatar.dart';

class MessageOrderScreen extends StatefulWidget {
  final String conversationId; // 1. Add this property
  final String farmerId;
  final String productId;
  final String farmerName;
  final String? farmerPhotoUrl;
  final String productName;
  final String productPrice;
  final String productImage;
  final bool deliveryAvailable;
  final bool pickupAvailable;
  final String? unit;

  const MessageOrderScreen({
    super.key,
    required this.conversationId, // 2. Add this parameter requirement
    required this.farmerId,
    required this.productId,
    required this.farmerName,
    this.farmerPhotoUrl,
    required this.productName,
    required this.productPrice,
    required this.productImage,
    required this.deliveryAvailable,
    required this.pickupAvailable,
    this.unit,
  });

  @override
  State<MessageOrderScreen> createState() => _MessageOrderScreenState();
}

class _MessageOrderScreenState extends State<MessageOrderScreen> {
  final MessageService _messageService = MessageService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  late final String _conversationId;
  // Created once, never in build() — see ChatScreen: a stream made in
  // build() re-subscribes on every rebuild (e.g. when the keyboard opens)
  // and flashes the loading spinner over the conversation.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream =
      _messageService.messagesStream(widget.conversationId);
  // Last messages received, kept on screen if the stream hiccups.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastDocs;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
  _farmerProfileStream = FirebaseFirestore.instance
      .collection('publicProfiles')
      .doc(widget.farmerId)
      .snapshots();
  bool _sending = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Lets a Search conversation result scroll to its message.
  final MessageJumpTargets _jumpTargets = MessageJumpTargets();
  Map<String, dynamic>? _replyTo;
  double _horizontalDragDistance = 0;
  final ConversationPrefs _prefs = ConversationPrefs.instance;

  /// The farmer's nickname in this conversation if the buyer set one, else
  /// their real name. Display only — replies, orders and reports keep
  /// widget.farmerName.
  String get _name => _prefs.displayName(_conversationId, widget.farmerName);

  // Replies store the real name; show the nickname for the farmer.
  String _replySenderLabel(Map<String, dynamic> replyTo) =>
      replyTo['senderId'] == widget.farmerId
      ? _name
      : (replyTo['senderName'] ?? 'Message').toString();

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _messageService.markConversationRead(_conversationId);
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(FirebaseAuth.instance.currentUser?.uid);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _jumpTargets.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController
            .position
            .minScrollExtent, // When reversed: true, minScrollExtent is the bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Puts [text] in the composer for the buyer to review and send (e.g. a
  // long-distance delivery request from the order screen).
  void _setDraft(String text) {
    _messageController.text = text;
    _messageController.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _messageService.sendMessage(
        conversationId: _conversationId,
        otherUserId: widget.farmerId,
        text: text,
        replyTo: _replyTo,
      );

      _messageController.clear();
      if (mounted) setState(() => _replyTo = null);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    }
  }

  Future<void> _refreshMessages() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,

      appBar: AgriAppBar(
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
            return;
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const BuyerMarketplaceScreen(initialIndex: 1),
            ),
          );
        },

        titleWidget: Row(
          children: [
            // Live from publicProfiles so a photo change shows up here too.
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _farmerProfileStream,
              builder: (context, snapshot) {
                final livePhotoUrl = snapshot.data
                    ?.data()?['photoUrl']
                    ?.toString();
                return ProfileAvatar(
                  photoUrl: snapshot.hasData
                      ? livePhotoUrl
                      : widget.farmerPhotoUrl,
                  name: _name,
                  radius: 18,
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgriAppBar.titleStyle(size: 16),
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Conversation info',
            onPressed: _openInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            ChatProductCard(
              productId: widget.productId,
              fallbackName: widget.productName,
              fallbackImageUrl: widget.productImage,
              sellerId: widget.farmerId,
              sellerName: widget.farmerName,
              viewerIsFarmer: false,
              onDraftMessage: _setDraft,
            ),

            Expanded(
              child: AgriRefreshIndicator(
                color: AppTheme.dark,
                onRefresh: _refreshMessages,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) _lastDocs = snapshot.data!.docs;
                    final cached = _lastDocs;
                    if (cached == null) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Unable to load conversation.'),
                        );
                      }
                      return const ChatMessagesLoadingBar();
                    }
                    final docs = cached;
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'This conversation is empty. Send the first message to start.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse:
                          true, // Required so index 0 stays at the bottom and new messages stack below
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 5, 14, 10),
                      itemCount: docs.length,
                      itemBuilder: (context, index) => _jumpTargets.wrap(
                        docs[index].id,
                        Builder(
                          builder: (context) {
                            final data = docs[index].data();
                            final isMe =
                                data['senderId'] ==
                                FirebaseAuth.instance.currentUser!.uid;
                            final text = data['text']?.toString() ?? '';
                            final imageUrl = data['imageUrl']?.toString();

                            final timestamp = data['createdAt'] as Timestamp?;
                            if (data['type'] == 'pricingOptions') {
                              return OrderOptionsMessageCard(
                                data: data,
                                sellerId: widget.farmerId,
                                sellerName: widget.farmerName,
                                fallbackProductId: widget.productId,
                                fallbackProductName: widget.productName,
                                fallbackUnit: widget.unit,
                                onDraftMessage: _setDraft,
                              );
                            }
                            if (data['type'] == 'location') {
                              return _locationMessage(data, isMe);
                            }

                            return _buildMessage(
                              docs[index].id,
                              text,
                              isMe,
                              timestamp: timestamp,
                              imageUrl: imageUrl,
                              replyTo: data['replyTo'] is Map
                                  ? Map<String, dynamic>.from(
                                      data['replyTo'] as Map,
                                    )
                                  : null,
                              onReply: isMe
                                  ? null
                                  : () => _setReplyTarget(data, docs[index].id),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  // The composer's + button: Camera, Choose Photo or Share Location. Each
  // asks for its own permission only when chosen (see chat_attachments.dart).
  Future<void> _attach(BuildContext plusButtonContext) async {
    if (_sending) return;
    final choice = await showChatAttachmentMenu(plusButtonContext);
    if (!mounted || choice == null) return;
    switch (choice) {
      case ChatAttachment.camera:
        await _sendPhoto(ImageSource.camera);
      case ChatAttachment.gallery:
        await _sendPhoto(ImageSource.gallery);
      case ChatAttachment.location:
        await _shareLocation();
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final picked = await pickChatPhoto(context, source);
    if (picked == null || !mounted || _sending) return;

    setState(() => _sending = true);
    try {
      final imageUrl = await _cloudinaryService.uploadImage(picked);
      if (imageUrl == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to upload image.')),
        );
        return;
      }

      await _messageService.sendImageMessage(
        conversationId: _conversationId,
        otherUserId: widget.farmerId,
        imageUrl: imageUrl,
      );

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Optional and never automatic: confirmed first, then location permission
  // (only now), then sent to this chat only.
  Future<void> _shareLocation() async {
    if (_sending) return;
    try {
      final position = await getLocationToShare(context, otherUserName: _name);
      if (position == null || !mounted) return;
      setState(() => _sending = true);
      await _messageService.sendLocationMessage(
        conversationId: _conversationId,
        otherUserId: widget.farmerId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not share your location. Check your internet connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // A location shared for delivery/pick-up coordination: shown only as
  // "shared their location" with a View on Map button, never as an address.
  Widget _locationMessage(Map<String, dynamic> data, bool isMe) {
    const dark = AppTheme.dark;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMe ? dark : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 18,
                  color: isMe ? Colors.white : dark,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isMe
                        ? 'You shared your location'
                        : '$_name shared their location',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => MapsLauncher.open(
                  context,
                  latitude: (data['latitude'] as num?)?.toDouble(),
                  longitude: (data['longitude'] as num?)?.toDouble(),
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('View on Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isMe ? Colors.white : dark,
                  side: BorderSide(color: isMe ? Colors.white70 : dark),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Conversation Info (nickname, search, photos, product, pin/mute/archive,
  // report/block). It returns a message id when a search result is picked.
  Future<void> _openInfo() async {
    final messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationInfoScreen(
          conversationId: _conversationId,
          otherUserId: widget.farmerId,
          otherUserName: widget.farmerName,
          otherUserPhotoUrl: widget.farmerPhotoUrl,
          productId: widget.productId,
          productName: widget.productName,
        ),
      ),
    );
    if (!mounted) return;
    // Blocked from Conversation Info: this chat is now hidden, so leave it.
    if (_prefs.isBlocked(widget.farmerId)) {
      Navigator.maybePop(context);
      return;
    }
    if (messageId == null) return;
    final found = await _jumpTargets.jumpTo(_scrollController, messageId);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t find that message.')),
      );
    }
  }

  void _setReplyTarget(Map<String, dynamic> message, String messageId) {
    final senderId = (message['senderId'] ?? '').toString();
    final text = (message['text'] ?? '').toString().trim();
    final imageUrl = (message['imageUrl'] ?? '').toString();
    final quote = text.isNotEmpty
        ? text
        : imageUrl.isNotEmpty
        ? 'Photo'
        : 'Message';
    setState(() {
      _replyTo = {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderId == FirebaseAuth.instance.currentUser?.uid
            ? 'You'
            : widget.farmerName,
        'text': quote,
      };
    });
  }

  Widget _buildMessage(
    String messageId,
    String message,
    bool isMe, {
    Timestamp? timestamp,
    String? imageUrl,
    Map<String, dynamic>? replyTo,
    VoidCallback? onReply,
  }) {
    String timeString = '';
    if (timestamp != null) {
      final dateTime = timestamp.toDate();
      timeString = TimeOfDay.fromDateTime(dateTime).format(context);
    }

    return GestureDetector(
      onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
      onHorizontalDragUpdate: (details) {
        if (!isMe) _horizontalDragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        if (!isMe && _horizontalDragDistance > 48) onReply?.call();
        _horizontalDragDistance = 0;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE8F5E9),
                ),
                child: const Icon(Icons.person, size: 16, color: AppTheme.dark),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isMe ? AppTheme.dark : const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replyTo != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(7),
                        margin: const EdgeInsets.only(bottom: 7),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.14)
                              : const Color(0xFFEAF4E7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: isMe ? Colors.white70 : AppTheme.dark,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          '${_replySenderLabel(replyTo)}: ${replyTo['text']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              height: 120,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppTheme.dark,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(
                                height: 120,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    if (imageUrl != null &&
                        imageUrl.isNotEmpty &&
                        message.isNotEmpty)
                      const SizedBox(height: 8),
                    if (message.isNotEmpty)
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isMe ? Colors.white : Colors.black87,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (timeString.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  timeString,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 17,
                    color: AppTheme.dark,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Replying to ${_replySenderLabel(_replyTo!)}: ${_replyTo!['text']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close, size: 17),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ChatComposerBar(
            controller: _messageController,
            hintText: 'Message $_name...',
            sending: _sending,
            onSend: _sendMessage,
            onAttach: _attach,
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({required this.text, required this.isMe});
}
