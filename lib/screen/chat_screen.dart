import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/message_service.dart';
import '../services/cloudinary_service.dart';
import '../services/location_permission_prompt.dart';
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

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    // Zero out this user's unread badge for this thread as soon as they open it.
    _messageService.markConversationRead(widget.conversationId);
  }

  @override
  void dispose() {
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
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      ).showSnackBar(SnackBar(content: Text('Failed to send image: $error')));
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
        const SnackBar(content: Text('Could not share your location. Please try again.')),
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
        const SnackBar(content: Text('Could not send pricing options.')),
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
          productPrice: '₱${price.toStringAsFixed(2)}/kg',
          productImage: widget.productImageUrl ?? '',
          deliveryAvailable: false,
          pickupAvailable: false,
          pricingType: pricingType,
          minimumQuantity: minimumQuantity,
          maximumQuantity: maximumQuantity,
          initialQuantity: initialQuantity,
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
                                return _pricingOptionsMessage(data);
                              }
                              if (data['type'] == 'location') {
                                return _locationMessage(data);
                              }
                              return _messageBubble(
                                text,
                                isMe,
                                ts?.toDate(),
                                imageUrl: imageUrl,
                              );
                            },
                          ),
                  );
                },
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(
    String text,
    bool isMe,
    DateTime? time, {
    String? imageUrl,
  }) {
    return Align(
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
        ],
      ),
    );
  }

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
              'Retail (maximum $retailMaximumQuantity)',
              retailPrice,
              'retail',
              1,
              retailMaximumQuantity,
              isMe,
            ),
            if (wholesalePrice != null && wholesalePrice > 0)
              _priceChoice(
                'Wholesale (minimum $minimumQuantity)',
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
                    Text(
                      isMe ? 'You shared your location' : '${widget.otherUserName} shared their location',
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
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
          '$label: ₱${price.toStringAsFixed(2)}/kg',
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
          child: Text('$label - ₱${price.toStringAsFixed(2)}/kg'),
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
      child: Row(
        children: [
          IconButton(
            tooltip: 'Send photo',
            onPressed: _sending ? null : _sendImage,
            icon: const Icon(Icons.camera_alt_outlined, color: _dark),
          ),
          IconButton(
            tooltip: 'Share location',
            onPressed: _sending ? null : _shareLocation,
            icon: const Icon(Icons.location_on_outlined, color: _dark),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message ${widget.otherUserName}...',
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
    );
  }

  String _formatBubbleTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}
