import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/message_service.dart';
import '../services/cloudinary_service.dart';
import '../services/location_permission_prompt.dart';
import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import '../widgets/open_in_maps_button.dart';
import '../widgets/pricing_calculator_sheet.dart';
import 'place_order_screen.dart';

/// A single conversation thread — real-time, Messenger-style.
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final bool isFarmer;
  final String? productId;
  final String? productName;
  final String? productImageUrl;
  final Uint8List? productImageBytes;
  final num? retailPrice;
  final num? wholesalePrice;
  final int wholesaleMinimumQuantity;
  final int retailMaximumQuantity;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.isFarmer = false,
    this.productId,
    this.productName,
    this.productImageUrl,
    this.productImageBytes,
    this.retailPrice,
    this.wholesalePrice,
    this.wholesaleMinimumQuantity = 1,
    this.retailMaximumQuantity = 1,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _bg = Colors.white;

  final MessageService _messageService = MessageService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  Timer? _typingTimer;
  Timer? _typingExpiryTimer;
  Timer? _likeHoldTimer;
  bool _typingActive = false;
  Map<String, dynamic>? _replyTo;
  double _horizontalDragDistance = 0;
  String? _lastReadMarkedMessageId;
  DateTime? _typingExpiryFor;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  // The commodity's Unit of Measurement (see commodity_master_list.dart),
  // derived from the product name — used everywhere this screen would
  // otherwise have hardcoded "/kg".
  String get _unit => unitForProductName(widget.productName ?? '');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onComposerChanged);
    // Zero out this user's unread badge for this thread as soon as they open it.
    _messageService.markConversationRead(widget.conversationId).catchError((_) {});
  }

  void _onComposerChanged() {
    final isTyping = _controller.text.trim().isNotEmpty;
    if (isTyping && !_typingActive) {
      _typingActive = true;
      _messageService.setTyping(widget.conversationId, true).catchError((_) {});
    }
    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    } else {
      _stopTyping();
    }
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (!_typingActive) return;
    _typingActive = false;
    _messageService.setTyping(widget.conversationId, false).catchError((_) {});
  }

  void _beginLikeHold(String messageId, Offset position) {
    _likeHoldTimer?.cancel();
    // Flutter's long-press recognizer starts after about half a second; this
    // additional half-second makes the reaction appear after roughly 1s held.
    _likeHoldTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _showLikePicker(messageId, position);
    });
  }

  Future<void> _showLikePicker(String messageId, Offset position) async {
    final size = MediaQuery.of(context).size;
    final reaction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        (position.dx - 80).clamp(8, size.width - 8).toDouble(),
        (position.dy - 64).clamp(8, size.height - 8).toDouble(),
        (size.width - position.dx - 80).clamp(8, size.width - 8).toDouble(),
        (size.height - position.dy).clamp(8, size.height - 8).toDouble(),
      ),
      items: const [
        PopupMenuItem(value: 'like', child: Text('👍  Like')),
      ],
    );
    if (reaction == 'like') {
      try {
        await _messageService.toggleLike(widget.conversationId, messageId);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not react to this message.')),
        );
      }
    }
  }

  Widget _lastMessageStatus(DateTime sentAt, bool isPending) {
    if (isPending) {
      return Text('Sending…', style: TextStyle(fontSize: 10, color: Colors.grey[500]));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _messageService.readReceiptStream(widget.conversationId, widget.otherUserId),
      builder: (context, snapshot) {
        final raw = snapshot.data?.data()?['lastReadAt'];
        final readAt = raw is Timestamp ? raw.toDate() : null;
        final seen = readAt != null && !readAt.isBefore(sentAt);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(seen ? Icons.done_all_rounded : Icons.done_rounded,
                size: 12, color: seen ? Colors.blue : Colors.grey[500]),
            const SizedBox(width: 3),
            Text(seen ? 'Seen' : 'Sent',
                style: TextStyle(fontSize: 10, color: seen ? Colors.blue : Colors.grey[500])),
          ],
        );
      },
    );
  }

  Widget _withDeliveryStatus(
    Widget message, {
    required bool isMe,
    required bool isLastOutgoing,
    required bool isPending,
    required DateTime? time,
  }) {
    if (!isMe) return message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        message,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: isLastOutgoing && time != null
              ? _lastMessageStatus(time, isPending)
              : Text(isPending ? 'Sending…' : 'Sent',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ),
      ],
    );
  }

  Widget _typingIndicator() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _messageService.typingStream(widget.conversationId, widget.otherUserId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final updatedAt = data?['updatedAt'];
        final updated = updatedAt is Timestamp ? updatedAt.toDate() : null;
        final active = data?['isTyping'] == true &&
            updated != null &&
            DateTime.now().difference(updated) < const Duration(seconds: 8);
        if (active && updated != _typingExpiryFor) {
          _typingExpiryFor = updated;
          _typingExpiryTimer?.cancel();
          final remaining = const Duration(seconds: 8) - DateTime.now().difference(updated);
          _typingExpiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
            if (mounted) setState(() {});
          });
        }
        if (!active) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${widget.otherUserName} is typing…',
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _typingExpiryTimer?.cancel();
    _likeHoldTimer?.cancel();
    _controller.removeListener(_onComposerChanged);
    if (_typingActive) {
      _messageService.setTyping(widget.conversationId, false).catchError((_) {});
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await _messageService.sendMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        text: text,
        replyTo: _replyTo,
      );
      if (mounted) setState(() => _replyTo = null);
    } catch (_) {
      if (!mounted) return;
      if (_controller.text.isEmpty) _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection. Your message was not sent. Reconnect and try again.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setReplyTarget(Map<String, dynamic> message, String messageId) {
    final senderId = (message['senderId'] ?? '').toString();
    final isMe = senderId == _myUid;
    final text = (message['text'] ?? '').toString().trim();
    final imageUrl = (message['imageUrl'] ?? '').toString();
    final quote = text.isNotEmpty
        ? text
        : imageUrl.isNotEmpty
            ? 'Photo'
            : message['type'] == 'location'
                ? 'Location'
                : message['type'] == 'pricingOptions'
                    ? 'Pricing options'
                    : 'Message';
    setState(() {
      _replyTo = {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': isMe
          ? (FirebaseAuth.instance.currentUser?.displayName ?? 'You')
          : widget.otherUserName,
        'text': quote,
      };
    });
  }

  Future<void> _sendImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || _sending) return;

    setState(() => _sending = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (picked == null) return;
      final imageUrl = await _cloudinaryService.uploadImage(picked);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw StateError('Unable to upload image.');
      }
      await _messageService.sendImageMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        imageUrl: imageUrl,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('Could not send image. Check your internet connection and try again. ($error)')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareLocation() async {
    if (_sending) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Share your location?'),
        content: Text(
          'Your current location will be sent to ${widget.otherUserName} as a message.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Share')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final granted = await maybeRequestLocationPermission(
        context,
        title: 'Share your location',
        message: 'AgriTrade+ uses your current GPS position to share it in this chat.',
      );
      if (!granted) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on location services to share your location.')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _messageService.sendLocationMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share your location. Check your internet connection and try again.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reportUser() async {
    final reportController = TextEditingController();
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report ${widget.otherUserName}'),
        content: TextField(
          controller: reportController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Explain the issue...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    final description = reportController.text.trim();
    reportController.dispose();
    if (shouldSend != true || description.isEmpty || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('reports').add({
        'issueType': 'Chat Report',
        'description': description,
        'reporterId': user?.uid ?? '',
        'reporterName': user?.displayName ?? 'User',
        'reportedUserId': widget.otherUserId,
        'reportedUserName': widget.otherUserName,
        // The Moderation Queue's report-target model: a chat report always
        // concerns the other participant's account/behavior, not a specific
        // listing, so targetType is 'farmer' and farmerId is that participant.
        'targetType': 'farmer',
        'farmerId': widget.otherUserId,
        'conversationId': widget.conversationId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report sent for review.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not send report.')));
    }
  }

  bool get _hasProductPreview =>
      widget.productName != null && widget.productName!.isNotEmpty;

  Future<void> _sendPricingOptions() async {
    var retailPrice = widget.retailPrice;
    var wholesalePrice = widget.wholesalePrice;
    var wholesaleMinimumQuantity = widget.wholesaleMinimumQuantity;
    var retailMaximumQuantity = widget.retailMaximumQuantity;
    if (retailPrice == null &&
        widget.productId != null &&
        widget.productId!.isNotEmpty) {
      try {
        final product = await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .get();
        final productData = product.data();
        retailPrice = productData?['price'] as num?;
        wholesalePrice = productData?['wholesalePrice'] as num?;
        wholesaleMinimumQuantity =
            (productData?['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1;
        retailMaximumQuantity =
            (productData?['retailMaximumQuantity'] as num?)?.toInt() ?? 1;
      } catch (_) {
        // The message can still be used if the product lookup is unavailable.
      }
    }
    if (retailPrice == null || retailPrice <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pricing information is unavailable for this product.'),
        ),
      );
      return;
    }
    try {
      await _messageService.sendPricingOptions(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
        wholesaleMinimumQuantity: wholesaleMinimumQuantity,
        retailMaximumQuantity: retailMaximumQuantity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing options sent to the buyer.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send pricing options. Check your internet connection and try again.')),
      );
    }
  }

  Future<void> _choosePrice(
    num price,
    String pricingType,
    int minimumQuantity,
    int maximumQuantity, {
    int? initialQuantity,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceOrderScreen(
          sellerId: widget.otherUserId,
          sellerName: widget.otherUserName,
          productId: widget.productId ?? '',
          productName: widget.productName ?? 'Product',
          productPrice: formatPriceWithUnit(price, _unit),
          productImage: widget.productImageUrl ?? '',
          deliveryAvailable: false,
          pickupAvailable: false,
          pricingType: pricingType,
          minimumQuantity: minimumQuantity,
          maximumQuantity: maximumQuantity,
          initialQuantity: initialQuantity,
          unit: _unit,
        ),
      ),
    );
  }

  void _openPricingCalculator(
    num price,
    String pricingType,
    int minimumQuantity,
    int maximumQuantity,
  ) {
    showPricingCalculatorSheet(
      context,
      pricingType: pricingType,
      unitPrice: price,
      minimumQuantity: minimumQuantity,
      maximumQuantity: maximumQuantity,
      unit: _unit,
      onProceed: (quantity) => _choosePrice(
        price,
        pricingType,
        minimumQuantity,
        maximumQuantity,
        initialQuantity: quantity,
      ),
    );
  }

  void _startNegotiation() {
    final productName = widget.productName ?? 'this product';
    _controller.text = 'I would like to negotiate the price for $productName.';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: _dark),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _accent,
              child: Text(
                widget.otherUserName.isNotEmpty
                    ? widget.otherUserName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: _dark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Report user',
              onPressed: _reportUser,
              icon: const Icon(Icons.flag_outlined, color: _dark),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_hasProductPreview) _productPreview(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messageService.messagesStream(widget.conversationId),
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

                  final docs = snapshot.data?.docs ?? [];
                  final latestIncomingIndex = docs.indexWhere(
                    (doc) => doc.data()['senderId'] != _myUid,
                  );
                  if (latestIncomingIndex >= 0 &&
                      _lastReadMarkedMessageId != docs[latestIncomingIndex].id) {
                    _lastReadMarkedMessageId = docs[latestIncomingIndex].id;
                    _messageService
                        .markConversationRead(widget.conversationId)
                        .catchError((_) {});
                  }
                  final latestOutgoingIndex = docs.indexWhere(
                    (doc) => doc.data()['senderId'] == _myUid,
                  );

                  return RefreshIndicator(
                    color: _dark,
                    onRefresh: () async {
                      await Future.delayed(const Duration(milliseconds: 700));
                      if (mounted) setState(() {});
                    },
                    child: docs.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Say hello to ${widget.otherUserName} 👋',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: docs.length,
                            itemBuilder: (context, i) {
                              final data = docs[i].data();
                              final isMe = data['senderId'] == _myUid;
                              final text = data['text']?.toString() ?? '';
                              final imageUrl = data['imageUrl']?.toString();
                              final ts = data['createdAt'] as Timestamp?;
                              if (data['type'] == 'pricingOptions') {
                                return _replyGesture(
                                  messageId: docs[i].id,
                                  data: data,
                                  isMe: isMe,
                                  child: _withDeliveryStatus(
                                    _reactableSpecialMessage(
                                      docs[i].id,
                                      _pricingOptionsMessage(data),
                                      Map<String, dynamic>.from(data['likes'] ?? {}),
                                    ),
                                    isMe: isMe,
                                    isLastOutgoing: i == latestOutgoingIndex,
                                    isPending: docs[i].metadata.hasPendingWrites,
                                    time: ts?.toDate(),
                                  ),
                                );
                              }
                              if (data['type'] == 'location') {
                                return _replyGesture(
                                  messageId: docs[i].id,
                                  data: data,
                                  isMe: isMe,
                                  child: _withDeliveryStatus(
                                    _reactableSpecialMessage(
                                      docs[i].id,
                                      _locationMessage(data),
                                      Map<String, dynamic>.from(data['likes'] ?? {}),
                                    ),
                                    isMe: isMe,
                                    isLastOutgoing: i == latestOutgoingIndex,
                                    isPending: docs[i].metadata.hasPendingWrites,
                                    time: ts?.toDate(),
                                  ),
                                );
                              }
                              return _messageBubble(
                                docs[i].id,
                                text,
                                isMe,
                                ts?.toDate(),
                                imageUrl: imageUrl,
                                isLastOutgoing: i == latestOutgoingIndex,
                                isPending: docs[i].metadata.hasPendingWrites,
                                likes: Map<String, dynamic>.from(data['likes'] ?? {}),
                                replyTo: data['replyTo'] is Map
                                    ? Map<String, dynamic>.from(data['replyTo'] as Map)
                                    : null,
                                onReply: isMe ? null : () => _setReplyTarget(data, docs[i].id),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
            _typingIndicator(),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(
    String messageId,
    String text,
    bool isMe,
    DateTime? time, {
    String? imageUrl,
    bool isLastOutgoing = false,
    bool isPending = false,
    Map<String, dynamic> likes = const {},
    Map<String, dynamic>? replyTo,
    VoidCallback? onReply,
  }) {
    return GestureDetector(
      onLongPressStart: (details) => _beginLikeHold(messageId, details.globalPosition),
      onLongPressEnd: (_) => _likeHoldTimer?.cancel(),
      onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
      onHorizontalDragUpdate: (details) {
        if (!isMe) _horizontalDragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        if (!isMe && _horizontalDragDistance > 48) onReply?.call();
        _horizontalDragDistance = 0;
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            decoration: BoxDecoration(
              color: isMe ? _dark : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: isMe
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replyTo != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(7),
                    margin: const EdgeInsets.only(bottom: 7),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.white.withValues(alpha: 0.14) : const Color(0xFFEAF4E7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(left: BorderSide(color: isMe ? Colors.white70 : _dark, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replyTo['senderId'] == _myUid
                              ? 'You'
                              : (replyTo['senderName'] ?? 'Message').toString(),
                          style: TextStyle(color: isMe ? Colors.white : _dark, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          (replyTo['text'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isMe ? Colors.white70 : Colors.black54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
                if (imageUrl != null && imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const SizedBox(
                              height: 120,
                              child: Center(
                                child: CircularProgressIndicator(color: _dark),
                              ),
                            ),
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
                if (imageUrl != null && imageUrl.isNotEmpty && text.isNotEmpty)
                  const SizedBox(height: 8),
                if (text.isNotEmpty)
                  Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14.5,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _formatBubbleTime(time),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
            if (likes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 5, bottom: 2),
                child: Text('👍 ${likes.values.where((value) => value == true).length}',
                    style: const TextStyle(fontSize: 11)),
              ),
            if (isMe)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: isLastOutgoing && time != null
                    ? _lastMessageStatus(time, isPending)
                    : Text(
                        isPending ? 'Sending…' : 'Sent',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _replyGesture({
    required String messageId,
    required Map<String, dynamic> data,
    required bool isMe,
    required Widget child,
  }) {
    return GestureDetector(
      onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
      onHorizontalDragUpdate: (details) {
        if (!isMe) _horizontalDragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        if (!isMe && _horizontalDragDistance > 48) {
          _setReplyTarget(data, messageId);
        }
        _horizontalDragDistance = 0;
      },
      child: child,
    );
  }

  Widget _reactableSpecialMessage(
    String messageId,
    Widget message,
    Map<String, dynamic> likes,
  ) => GestureDetector(
        onLongPressStart: (details) => _beginLikeHold(messageId, details.globalPosition),
        onLongPressEnd: (_) => _likeHoldTimer?.cancel(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message,
            if (likes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: Text('👍 ${likes.values.where((value) => value == true).length}',
                    style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
      );

  Widget _productPreview() {
    return InkWell(
      onTap: _startNegotiation,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 64,
                height: 64,
                child: widget.productImageBytes != null
                    ? Image.memory(widget.productImageBytes!, fit: BoxFit.cover)
                    : (widget.productImageUrl != null &&
                          widget.productImageUrl!.isNotEmpty)
                    ? Image.network(
                        widget.productImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: _accent,
                          child: Icon(Icons.broken_image, color: _dark),
                        ),
                      )
                    : const ColoredBox(
                        color: _accent,
                        child: Icon(Icons.eco_rounded, color: _dark),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.productName ?? 'Product',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.isFarmer
                        ? 'Send retail or wholesale pricing options.'
                        : 'Tap to negotiate this product.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  if (widget.isFarmer) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _sendPricingOptions,
                      icon: const Icon(Icons.sell_outlined, size: 16),
                      label: const Text('Send options'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _dark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pricingOptionsMessage(Map<String, dynamic> data) {
    final isMe = data['senderId'] == _myUid;
    final retailPrice = (data['retailPrice'] as num?)?.toDouble() ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final minimumQuantity =
        (data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1;
    final retailMaximumQuantity =
        (data['retailMaximumQuantity'] as num?)?.toInt() ?? 1;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isMe ? _dark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isMe
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose an order type',
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _priceChoice(
              'Retail (maximum $retailMaximumQuantity $_unit)',
              retailPrice,
              'retail',
              1,
              retailMaximumQuantity,
              isMe,
            ),
            if (wholesalePrice != null && wholesalePrice > 0)
              _priceChoice(
                'Wholesale (minimum $minimumQuantity $_unit)',
                wholesalePrice,
                'wholesale',
                minimumQuantity,
                0,
                isMe,
              ),
          ],
        ),
      ),
    );
  }

  Widget _locationMessage(Map<String, dynamic> data) {
    final isMe = data['senderId'] == _myUid;
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    final ts = data['createdAt'] as Timestamp?;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.all(14),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isMe ? _dark : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: isMe
                  ? null
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, size: 18, color: isMe ? Colors.white : _dark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isMe ? 'You shared your location' : '${widget.otherUserName} shared their location',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                    onPressed: () => MapsLauncher.open(context, latitude: latitude, longitude: longitude),
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('View on Map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isMe ? Colors.white : _dark,
                      side: BorderSide(color: isMe ? Colors.white70 : _dark),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (ts != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_formatBubbleTime(ts.toDate()), style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ),
        ],
      ),
    );
  }

  Widget _priceChoice(
    String label,
    num price,
    String type,
    int minimumQuantity,
    int maximumQuantity,
    bool isMe,
  ) {
    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '$label: ${formatPriceWithUnit(price, _unit)}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _openPricingCalculator(
              price, type, minimumQuantity, maximumQuantity),
          child: Text('$label - ${formatPriceWithUnit(price, _unit)}'),
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 17, color: _dark),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Replying to ${_replyTo!['senderName']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('${_replyTo!['text']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close, size: 17),
                  ),
                ],
              ),
            ),
          Row(
            children: [
          IconButton(
            tooltip: 'Send photo',
            onPressed: _sending ? null : _sendImage,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: const EdgeInsets.all(2),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.camera_alt_outlined, color: _dark, size: 18),
          ),
          IconButton(
            tooltip: 'Share location',
            onPressed: _sending ? null : _shareLocation,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: const EdgeInsets.all(2),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.location_on_outlined, color: _dark, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message ${widget.otherUserName}...',
                isDense: true,
                filled: true,
                fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _sending ? null : _send,
            customBorder: const CircleBorder(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _sending ? Colors.grey[400] : _dark,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatBubbleTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}
