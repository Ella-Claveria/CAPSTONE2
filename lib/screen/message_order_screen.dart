import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';
import '../services/message_service.dart';
import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import '../widgets/pricing_calculator_sheet.dart';
import 'buyer_marketplace_screen.dart';
import 'place_order_screen.dart';

class MessageOrderScreen extends StatefulWidget {
  final String conversationId; // 1. Add this property
  final String farmerId;
  final String productId;
  final String farmerName;
  final String productName;
  final String productPrice;
  final String productImage;
  final bool deliveryAvailable;
  final bool pickupAvailable;

  const MessageOrderScreen({
    super.key,
    required this.conversationId, // 2. Add this parameter requirement
    required this.farmerId,
    required this.productId,
    required this.farmerName,
    required this.productName,
    required this.productPrice,
    required this.productImage,
    required this.deliveryAvailable,
    required this.pickupAvailable,
  });

  @override
  State<MessageOrderScreen> createState() => _MessageOrderScreenState();
}

class _MessageOrderScreenState extends State<MessageOrderScreen> {
  final MessageService _messageService = MessageService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ImagePicker _picker = ImagePicker();
  late final String _conversationId;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // The commodity's Unit of Measurement (see commodity_master_list.dart),
  // derived from the product name — used everywhere this screen would
  // otherwise have hardcoded "/kg".
  String get _unit => unitForProductName(widget.productName);

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _messageService.markConversationRead(_conversationId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _messageService.sendMessage(
        conversationId: _conversationId,
        otherUserId: widget.farmerId,
        text: text,
      );

      _messageController.clear();
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

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () {
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
        ),

        titleSpacing: 0,

        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE8F5E9),
              ),
              child: const Icon(
                Icons.person,
                color: Color(0xFF16A34A),
                size: 25,
              ),
            ),

            const SizedBox(width: 10),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.farmerName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Online',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Report user',
            onPressed: _reportSeller,
            icon: const Icon(Icons.flag_outlined, color: Color(0xFF1B5E20)),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            _buildProductCard(),
            const SizedBox(height: 8),

            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF1B5E20),
                onRefresh: _refreshMessages,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messageService.messagesStream(_conversationId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Unable to load conversation.'),
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
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
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final isMe =
                            data['senderId'] ==
                            FirebaseAuth.instance.currentUser!.uid;
                        final text = data['text']?.toString() ?? '';
                        final imageUrl = data['imageUrl']?.toString();

                        final timestamp = data['createdAt'] as Timestamp?;
                        if (data['type'] == 'pricingOptions') {
                          return _pricingOptionsMessage(data);
                        }

                        return _buildMessage(
                          text,
                          isMe,
                          timestamp: timestamp,
                          imageUrl: imageUrl,
                        );
                      },
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

  Widget _buildProductCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: const Color(0xFFF1F1F1),
            ),
            child: widget.productImage.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.network(
                      widget.productImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) {
                        return const Icon(
                          Icons.shopping_basket,
                          color: Color(0xFF15803D),
                          size: 30,
                        );
                      },
                    ),
                  )
                : const Icon(
                    Icons.shopping_basket,
                    color: Color(0xFF15803D),
                    size: 30,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.productPrice,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF15803D),
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Laurel, Batangas',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _openPlaceOrderScreen,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14532D),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Order Now',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlaceOrderScreen() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceOrderScreen(
          sellerId: widget.farmerId,
          sellerName: widget.farmerName,
          productId: widget.productId,
          productName: widget.productName,
          productPrice: widget.productPrice,
          productImage: widget.productImage,
          deliveryAvailable: widget.deliveryAvailable,
          pickupAvailable: widget.pickupAvailable,
          unit: _unit,
        ),
      ),
    );

    if (!mounted || result != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order submitted successfully.')),
    );
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
          sellerId: widget.farmerId,
          sellerName: widget.farmerName,
          productId: widget.productId,
          productName: widget.productName,
          productPrice: formatPriceWithUnit(price, _unit),
          productImage: widget.productImage,
          deliveryAvailable: widget.deliveryAvailable,
          pickupAvailable: widget.pickupAvailable,
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

  Widget _pricingOptionsMessage(Map<String, dynamic> data) {
    final isMe = data['senderId'] == FirebaseAuth.instance.currentUser?.uid;
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
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF14532D) : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(16),
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
            if (isMe)
              Text(
                'Retail: ${formatPriceWithUnit(retailPrice, _unit)} (maximum $retailMaximumQuantity $_unit)',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              )
            else
              OutlinedButton(
                onPressed: () => _openPricingCalculator(
                  retailPrice,
                  'retail',
                  1,
                  retailMaximumQuantity,
                ),
                child: Text(
                  'Retail (maximum $retailMaximumQuantity $_unit) - ${formatPriceWithUnit(retailPrice, _unit)}',
                ),
              ),
            if (wholesalePrice != null && wholesalePrice > 0)
              if (isMe)
                Text(
                  'Wholesale (Bulk Orders): ${formatPriceWithUnit(wholesalePrice, _unit)} (minimum $minimumQuantity $_unit)',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                )
              else
                OutlinedButton(
                  onPressed: () => _openPricingCalculator(
                    wholesalePrice,
                    'wholesale',
                    minimumQuantity,
                    0,
                  ),
                  child: Text(
                    'Wholesale (Bulk Orders) - ${formatPriceWithUnit(wholesalePrice, _unit)} (min $minimumQuantity $_unit)',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
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
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (picked == null) return;

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
    }
  }

  Future<void> _reportSeller() async {
    final reportController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report Seller'),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report sent. Our team will review it.'),
                  ),
                );
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessage(
    String message,
    bool isMe, {
    Timestamp? timestamp,
    String? imageUrl,
  }) {
    String timeString = '';
    if (timestamp != null) {
      final dateTime = timestamp.toDate();
      timeString = TimeOfDay.fromDateTime(dateTime).format(context);
    }

    return Padding(
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
              child: const Icon(
                Icons.person,
                size: 16,
                color: Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF14532D) : const Color(0xFFF0F2F5),
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
                                color: Color(0xFF14532D),
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
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: _sendImage,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            icon: const Icon(
              Icons.camera_alt_outlined,
              color: Color(0xFF14532D),
              size: 22,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Message ${widget.farmerName}...',
                filled: true,
                fillColor: const Color(0xFFF7F9F5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF14532D),
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 16),
            ),
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
