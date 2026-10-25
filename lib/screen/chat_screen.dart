import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/commodity_master_list.dart';
import '../services/message_service.dart';
import '../services/cloudinary_service.dart';
import '../services/conversation_prefs_service.dart';
import '../widgets/open_in_maps_button.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/online_dot.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/receipt_message_card.dart';
import 'chat_attachments.dart';
import 'chat_product_context.dart';
import 'conversation_info_screen.dart';
import 'conversation_tools_screens.dart';
import '../services/chat_date_label.dart';

/// A single conversation thread — real-time, Messenger-style.
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final bool isFarmer;
  final String? productId;
  final String? productName;
  final String? productImageUrl;
  final Uint8List? productImageBytes;
  final num? retailPrice;
  final num? wholesalePrice;
  final int wholesaleMinimumQuantity;
  final int retailMaximumQuantity;

  /// Text to start the composer with (e.g. a long-distance delivery request
  /// from the order screen). Not sent until the user taps Send.
  final String? initialDraft;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    this.isFarmer = false,
    this.productId,
    this.productName,
    this.productImageUrl,
    this.productImageBytes,
    this.retailPrice,
    this.wholesalePrice,
    this.wholesaleMinimumQuantity = 1,
    this.retailMaximumQuantity = 1,
    this.initialDraft,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _bg = Colors.white;

  final MessageService _messageService = MessageService();
  // The other person's public profile, live — their real name and photo.
  // What the opener passed in (widget.otherUserName / otherUserPhotoUrl) is
  // only a placeholder until it loads: it can be out of date (a renamed
  // account, an old notification, an order's saved name).
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _otherProfileSub;
  Map<String, dynamic>? _otherProfile;
  bool _otherProfileLoaded = false;
  // Created once for this chat, never in build(). A stream made in build()
  // is a brand-new Firestore subscription on every rebuild — and opening
  // the keyboard rebuilds this screen (it reads MediaQuery) — so the
  // StreamBuilders dropped their data and flashed the loading spinner each
  // time the message box was tapped.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream =
      _messageService.messagesStream(widget.conversationId);
  // Last messages received, kept on screen if the stream hiccups.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastDocs;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _typingStream =
      _messageService.typingStream(widget.conversationId, widget.otherUserId);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _readReceiptStream =
      _messageService.readReceiptStream(
        widget.conversationId,
        widget.otherUserId,
      );
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Lets a Search conversation result scroll to its message.
  final MessageJumpTargets _jumpTargets = MessageJumpTargets();
  bool _sending = false;
  Timer? _typingTimer;
  Timer? _typingExpiryTimer;
  Timer? _likeHoldTimer;
  bool _typingActive = false;
  Map<String, dynamic>? _replyTo;
  double _horizontalDragDistance = 0;
  String? _lastReadMarkedMessageId;
  DateTime? _typingExpiryFor;

  // Product context. Opening a chat from a notification passes no product,
  // so it's filled in from the conversation doc (see _loadConversationContext).
  String? _productId;
  String? _productName;
  String? _productImageUrl;
  String? _farmerId;

  // A chat about a livestock listing: the buyer can ask for the animal's
  // health certificate with one tap (a suggestion over the message box)
  // until they have asked once; the farmer answers with a photo of it.
  bool _livestockProduct = false;
  bool _certificateAsked = false;
  String? _certificateCheckedFor;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  final ConversationPrefs _prefs = ConversationPrefs.instance;

  /// The other person's real name: from their live profile once it has
  /// loaded, else the name this chat was opened with.
  String get _realName {
    final live = _otherProfile?['name']?.toString().trim() ?? '';
    return live.isNotEmpty ? live : widget.otherUserName;
  }

  /// What this user calls the other person in this conversation: their
  /// nickname here if one is set (see Conversation Info), else their real
  /// name. Display only — anything saved or sent (replies, orders,
  /// reports) uses [_realName].
  String get _name => _prefs.displayName(widget.conversationId, _realName);

  /// The other person's photo: from their live profile once it has loaded.
  String? get _otherPhotoUrl {
    if (!_otherProfileLoaded) return widget.otherUserPhotoUrl;
    return _otherProfile?['photoUrl']?.toString();
  }

  // Replies store the real name; show the nickname for the other person.
  String _replySenderLabel(Map<String, dynamic> replyTo) =>
      replyTo['senderId'] == widget.otherUserId
      ? _name
      : (replyTo['senderName'] ?? 'Message').toString();

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load(FirebaseAuth.instance.currentUser?.uid);
    _controller.addListener(_onComposerChanged);
    _otherProfileSub = FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(widget.otherUserId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _otherProfile = snap.data();
            _otherProfileLoaded = true;
          });
        }, onError: (_) {});
    // Zero out this user's unread badge for this thread as soon as they open it.
    _messageService
        .markConversationRead(widget.conversationId)
        .catchError((_) {});
    _productId = widget.productId;
    _productName = widget.productName;
    _productImageUrl = widget.productImageUrl;
    _loadConversationContext();
    _checkCertificateSuggestion();
    final draft = widget.initialDraft;
    if (draft != null && draft.isNotEmpty) _setDraft(draft);
  }

  // Puts [text] in the composer for the user to review and send.
  void _setDraft(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _loadConversationContext() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .get();
      final data = snap.data();
      if (data == null || !mounted) return;
      String? text(String key) {
        final value = data[key]?.toString().trim() ?? '';
        return value.isEmpty ? null : value;
      }

      setState(() {
        _farmerId = text('farmerId');
        if (_productId == null || _productId!.isEmpty) {
          _productId = text('productId');
          _productName ??= text('productName');
          _productImageUrl ??= text('productImageUrl');
        }
      });
      _checkCertificateSuggestion();
    } catch (_) {
      // Best effort — the chat works without a product card.
    }
  }

  // Whether this chat's product is livestock, and whether this user has
  // already asked for its health certificate here. Checked once per
  // product; best effort — without it the suggestion just isn't shown.
  Future<void> _checkCertificateSuggestion() async {
    final productId = _productId;
    if (productId == null ||
        productId.isEmpty ||
        _certificateCheckedFor == productId) {
      return;
    }
    _certificateCheckedFor = productId;
    try {
      final product = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();
      if (!isLivestockCategory(product.data()?['category']?.toString())) {
        return;
      }
      final requests = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .where('kind', isEqualTo: MessageService.certificateRequestKind)
          .get();
      if (!mounted) return;
      setState(() {
        _livestockProduct = true;
        _certificateAsked = requests.docs.any(
          (d) => d.data()['senderId'] == _myUid,
        );
      });
    } catch (_) {}
  }

  // True when this user has sent a photo after message [index] (the list
  // is newest first, so those are the ones before it).
  bool _photoSentSince(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
  ) {
    for (var j = 0; j < index; j++) {
      final data = docs[j].data();
      if (data['senderId'] == _myUid &&
          (data['imageUrl']?.toString() ?? '').isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool get _showCertificateSuggestion =>
      _livestockProduct && !_certificateAsked && !_viewerIsFarmer;

  // The suggestion's one tap: sends the request as it reads.
  Future<void> _askForCertificate() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _messageService.sendMessage(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        text: MessageService.certificateRequestText,
        kind: MessageService.certificateRequestKind,
      );
      if (mounted) setState(() => _certificateAsked = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No internet connection. Your message was not sent. Reconnect and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // The farmer's answer to a certificate request: a photo of it, from the
  // camera or the gallery.
  Future<void> _sendCertificatePhoto(BuildContext chipContext) async {
    if (_sending) return;
    final source = await showChatPhotoMenu(chipContext);
    if (source == null || !mounted) return;
    await _sendPhoto(source);
  }

  // Farmer-side view of the product context. The card itself confirms this
  // against the listing's owner once the product loads.
  bool get _viewerIsFarmer =>
      widget.isFarmer || (_farmerId != null && _farmerId == _myUid);

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
      items: const [PopupMenuItem(value: 'like', child: Text('👍  Like'))],
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
      return Text(
        'Sending…',
        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _readReceiptStream,
      builder: (context, snapshot) {
        final raw = snapshot.data?.data()?['lastReadAt'];
        final readAt = raw is Timestamp ? raw.toDate() : null;
        final seen = readAt != null && !readAt.isBefore(sentAt);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              seen ? Icons.done_all_rounded : Icons.done_rounded,
              size: 12,
              color: seen ? Colors.blue : Colors.grey[500],
            ),
            const SizedBox(width: 3),
            Text(
              seen ? 'Seen' : 'Sent',
              style: TextStyle(
                fontSize: 10,
                color: seen ? Colors.blue : Colors.grey[500],
              ),
            ),
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
              : Text(
                  isPending ? 'Sending…' : 'Sent',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
        ),
      ],
    );
  }

  // The list is newest-first, so the message before docs[i] in time is
  // docs[i + 1]. The first message of each day gets that day's heading
  // above it, centered — "Today", "Yesterday", or the day and date.
  Widget _withDayHeading(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int i,
    Widget message,
  ) {
    DateTime? sentAt(int index) =>
        (docs[index].data()['createdAt'] as Timestamp?)?.toDate();
    final isOldest = i == docs.length - 1;
    // A message still being sent has no time yet; neither it nor the one
    // after it should be given a heading on that account.
    final previous = isOldest ? null : sentAt(i + 1) ?? sentAt(i);
    if (!startsNewChatDay(sentAt(i), previous)) return message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chatDayLabel(sentAt(i)),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ),
        ),
        message,
      ],
    );
  }

  Widget _typingIndicator() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _typingStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final updatedAt = data?['updatedAt'];
        final updated = updatedAt is Timestamp ? updatedAt.toDate() : null;
        final active =
            data?['isTyping'] == true &&
            updated != null &&
            DateTime.now().difference(updated) < const Duration(seconds: 8);
        if (active && updated != _typingExpiryFor) {
          _typingExpiryFor = updated;
          _typingExpiryTimer?.cancel();
          final remaining =
              const Duration(seconds: 8) - DateTime.now().difference(updated);
          _typingExpiryTimer = Timer(
            remaining.isNegative ? Duration.zero : remaining,
            () {
              if (mounted) setState(() {});
            },
          );
        }
        if (!active) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$_name is typing…',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _otherProfileSub?.cancel();
    _prefs.removeListener(_onPrefsChanged);
    _typingTimer?.cancel();
    _typingExpiryTimer?.cancel();
    _likeHoldTimer?.cancel();
    _controller.removeListener(_onComposerChanged);
    if (_typingActive) {
      _messageService
          .setTyping(widget.conversationId, false)
          .catchError((_) {});
    }
    _controller.dispose();
    _scrollController.dispose();
    _jumpTargets.dispose();
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
        const SnackBar(
          content: Text(
            'No internet connection. Your message was not sent. Reconnect and try again.',
          ),
        ),
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
        ? 'Order options'
        : 'Message';
    setState(() {
      _replyTo = {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': isMe
            ? (FirebaseAuth.instance.currentUser?.displayName ?? 'You')
            : _realName,
        'text': quote,
      };
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send image. Check your internet connection and try again. ($error)',
          ),
        ),
      );
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
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
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

  // Conversation Info (nickname, search, photos, product, pin/mute/archive,
  // report/block). It returns a message id when a search result is picked.
  Future<void> _openInfo() async {
    final messageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationInfoScreen(
          conversationId: widget.conversationId,
          otherUserId: widget.otherUserId,
          otherUserName: _realName,
          otherUserPhotoUrl: _otherPhotoUrl,
          productId: _productId,
          productName: _productName,
        ),
      ),
    );
    if (!mounted) return;
    // Blocked from Conversation Info: this chat is now hidden, so leave it.
    if (_prefs.isBlocked(widget.otherUserId)) {
      Navigator.pop(context);
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

  bool get _hasProductContext =>
      (_productId != null && _productId!.isNotEmpty) ||
      (_productName != null && _productName!.isNotEmpty);

  // Farmer: sends the order-options card for the product, at its current
  // prices (ChatProductCard has already shown the Send Options sheet).
  Future<void> _sendOrderOptions(ChatProduct product) async {
    try {
      await _messageService.sendPricingOptions(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        productId: product.id,
        productName: product.name,
        unit: product.unit,
        retailPrice: product.retailPrice,
        wholesaleEnabled: product.wholesaleEnabled,
        wholesalePrice: product.wholesalePrice,
        wholesaleMinimumQuantity: product.wholesaleMinimum ?? 1,
        deliveryAvailable: product.deliveryAvailable,
        pickupAvailable: product.pickupAvailable,
        deliveryLabel: product.deliveryLabel,
        pickupLabel: product.pickupLabel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order options sent to the buyer.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not send order options. Check your internet connection and try again.',
          ),
        ),
      );
    }
  }

  void _startNegotiation() {
    final productName = _productName ?? 'this product';
    _controller.text = 'I would like to negotiate the price for $productName.';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AgriAppBar(
        actions: [
          IconButton(
            tooltip: 'Conversation info',
            onPressed: _openInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
        titleWidget: Row(
          children: [
            // Name and photo both live from the profile (see
            // _otherProfileSub), so they always belong to the same person.
            Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAvatar(
                  photoUrl: _otherPhotoUrl,
                  name: _name,
                  radius: 18,
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  // Shown only while the other person is really online, as
                  // on the Messages list.
                  child: OnlineDot(
                    key: ValueKey(widget.otherUserId),
                    userId: widget.otherUserId,
                  ),
                ),
              ],
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_hasProductContext)
              ChatProductCard(
                productId: _productId ?? '',
                fallbackName: _productName ?? 'Product',
                fallbackImageUrl: _productImageUrl,
                fallbackImageBytes: widget.productImageBytes,
                sellerId: widget.otherUserId,
                sellerName: _realName,
                viewerIsFarmer: _viewerIsFarmer,
                onSendOptions: _sendOrderOptions,
                onTapDetails: _startNegotiation,
                onDraftMessage: _setDraft,
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasData) _lastDocs = snapshot.data!.docs;
                  final cached = _lastDocs;
                  if (cached == null) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Something went wrong loading messages.'),
                      );
                    }
                    return const ChatMessagesLoadingBar();
                  }

                  final docs = cached;
                  final latestIncomingIndex = docs.indexWhere(
                    (doc) => doc.data()['senderId'] != _myUid,
                  );
                  if (latestIncomingIndex >= 0 &&
                      _lastReadMarkedMessageId !=
                          docs[latestIncomingIndex].id) {
                    _lastReadMarkedMessageId = docs[latestIncomingIndex].id;
                    _messageService
                        .markConversationRead(widget.conversationId)
                        .catchError((_) {});
                  }
                  final latestOutgoingIndex = docs.indexWhere(
                    (doc) => doc.data()['senderId'] == _myUid,
                  );

                  return AgriRefreshIndicator(
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
                                  'Say hello to $_name 👋',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: docs.length,
                            itemBuilder: (context, i) => _withDayHeading(
                              docs,
                              i,
                              _jumpTargets.wrap(
                                docs[i].id,
                                Builder(
                                  builder: (context) {
                                    final data = docs[i].data();
                                    final isMe = data['senderId'] == _myUid;
                                    final text = data['text']?.toString() ?? '';
                                    final imageUrl = data['imageUrl']
                                        ?.toString();
                                    final ts = data['createdAt'] as Timestamp?;
                                    if (data['type'] == 'pricingOptions') {
                                      return _replyGesture(
                                        messageId: docs[i].id,
                                        data: data,
                                        isMe: isMe,
                                        child: _withDeliveryStatus(
                                          _reactableSpecialMessage(
                                            docs[i].id,
                                            OrderOptionsMessageCard(
                                              data: data,
                                              sellerId: widget.otherUserId,
                                              sellerName: _realName,
                                              fallbackProductId: _productId,
                                              fallbackProductName: _productName,
                                              onDraftMessage: _setDraft,
                                            ),
                                            Map<String, dynamic>.from(
                                              data['likes'] ?? {},
                                            ),
                                          ),
                                          isMe: isMe,
                                          isLastOutgoing:
                                              i == latestOutgoingIndex,
                                          isPending:
                                              docs[i].metadata.hasPendingWrites,
                                          time: ts?.toDate(),
                                        ),
                                      );
                                    }
                                    if (data['type'] == 'receipt') {
                                      return _withDeliveryStatus(
                                        _reactableSpecialMessage(
                                          docs[i].id,
                                          ReceiptMessageCard(
                                            data: data,
                                            isMe: isMe,
                                          ),
                                          Map<String, dynamic>.from(
                                            data['likes'] ?? {},
                                          ),
                                        ),
                                        isMe: isMe,
                                        isLastOutgoing:
                                            i == latestOutgoingIndex,
                                        isPending:
                                            docs[i].metadata.hasPendingWrites,
                                        time: ts?.toDate(),
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
                                            Map<String, dynamic>.from(
                                              data['likes'] ?? {},
                                            ),
                                          ),
                                          isMe: isMe,
                                          isLastOutgoing:
                                              i == latestOutgoingIndex,
                                          isPending:
                                              docs[i].metadata.hasPendingWrites,
                                          time: ts?.toDate(),
                                        ),
                                      );
                                    }
                                    final bubble = _messageBubble(
                                      docs[i].id,
                                      text,
                                      isMe,
                                      ts?.toDate(),
                                      imageUrl: imageUrl,
                                      isLastOutgoing: i == latestOutgoingIndex,
                                      isPending:
                                          docs[i].metadata.hasPendingWrites,
                                      likes: Map<String, dynamic>.from(
                                        data['likes'] ?? {},
                                      ),
                                      replyTo: data['replyTo'] is Map
                                          ? Map<String, dynamic>.from(
                                              data['replyTo'] as Map,
                                            )
                                          : null,
                                      onReply: isMe
                                          ? null
                                          : () => _setReplyTarget(
                                              data,
                                              docs[i].id,
                                            ),
                                    );
                                    // The buyer asked for the health
                                    // certificate: the farmer can answer
                                    // with a photo right here, until one
                                    // has been sent after the request.
                                    if (!isMe &&
                                        _viewerIsFarmer &&
                                        data['kind'] ==
                                            MessageService
                                                .certificateRequestKind &&
                                        !_photoSentSince(docs, i)) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          bubble,
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                              bottom: 6,
                                            ),
                                            child: ChatSuggestionChip(
                                              icon: Icons.photo_camera_outlined,
                                              label: 'Send a photo',
                                              onTap: _sending
                                                  ? null
                                                  : _sendCertificatePhoto,
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return bubble;
                                  },
                                ),
                              ),
                            ),
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
    // A photo on its own is shown as just the photo — no green or white
    // bubble around it.
    final imageOnly =
        imageUrl != null &&
        imageUrl.isNotEmpty &&
        text.isEmpty &&
        replyTo == null;
    return GestureDetector(
      onLongPressStart: (details) =>
          _beginLikeHold(messageId, details.globalPosition),
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
              padding: imageOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.of(context).size.width *
                    (imageOnly ? 0.62 : 0.72),
              ),
              decoration: imageOnly
                  ? null
                  : BoxDecoration(
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
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.14)
                            : AppTheme.tint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(
                            color: isMe ? Colors.white70 : _dark,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            replyTo['senderId'] == _myUid
                                ? 'You'
                                : _replySenderLabel(replyTo),
                            style: TextStyle(
                              color: isMe ? Colors.white : _dark,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            (replyTo['text'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.black54,
                              fontSize: 11,
                            ),
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
                                  child: CircularProgressIndicator(
                                    color: _dark,
                                  ),
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
                  if (imageUrl != null &&
                      imageUrl.isNotEmpty &&
                      text.isNotEmpty)
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
                child: Text(
                  '👍 ${likes.values.where((value) => value == true).length}',
                  style: const TextStyle(fontSize: 11),
                ),
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
    onLongPressStart: (details) =>
        _beginLikeHold(messageId, details.globalPosition),
    onLongPressEnd: (_) => _likeHoldTimer?.cancel(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        message,
        if (likes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: Text(
              '👍 ${likes.values.where((value) => value == true).length}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    ),
  );

  Widget _locationMessage(Map<String, dynamic> data) {
    final isMe = data['senderId'] == _myUid;
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    final ts = data['createdAt'] as Timestamp?;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.all(14),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 18,
                      color: isMe ? Colors.white : _dark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isMe
                            ? 'You shared your location'
                            : '$_name shared their location',
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
                    onPressed: () => MapsLauncher.open(
                      context,
                      latitude: latitude,
                      longitude: longitude,
                    ),
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
              child: Text(
                _formatBubbleTime(ts.toDate()),
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
        ],
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
                color: AppTheme.tint,
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
                        Text(
                          'Replying to ${_replySenderLabel(_replyTo!)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_replyTo!['text']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
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
          if (_showCertificateSuggestion)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChatSuggestionChip(
                  icon: Icons.health_and_safety_outlined,
                  label: MessageService.certificateRequestText,
                  onTap: _sending ? null : (_) => _askForCertificate(),
                ),
              ),
            ),
          ChatComposerBar(
            controller: _controller,
            hintText: 'Message $_name...',
            sending: _sending,
            onSend: _send,
            onAttach: _attach,
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
