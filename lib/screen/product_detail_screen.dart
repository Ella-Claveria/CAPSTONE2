import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/message_service.dart';
import '../services/product_service.dart';
import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import 'message_order_screen.dart';
import 'place_order_screen.dart';
import 'buyer_market_view.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  static const Color _bg = Colors.white;

  Uint8List? _imageBytes;
  String? _imageUrl;
  late Map<String, dynamic> _currentData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _productSub;
  bool _productUnavailable = false;
  bool _productLoadError = false;

  @override
  void initState() {
    super.initState();
    _currentData = Map<String, dynamic>.from(widget.data);
    _watchProduct();
    ProductService().logProductView(widget.productId);

    final b64 = widget.data['imageBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        _imageBytes = base64Decode(b64);
      } catch (_) {
        _imageBytes = null;
      }
    }

    if (_imageBytes == null) {
      final url = widget.data['imageUrl']?.toString();
      if (url != null && url.isNotEmpty) {
        _imageUrl = url;
      } else if (widget.data['imageUrls'] is List &&
          (widget.data['imageUrls'] as List).isNotEmpty) {
        _imageUrl = (widget.data['imageUrls'] as List).first?.toString();
      }
    }
  }

  void _watchProduct() {
    _productSub?.cancel();
    _productSub = FirebaseFirestore.instance
        .collection('products')
        .doc(widget.productId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final data = snapshot.data();
            setState(() {
              _productLoadError = false;
              final available =
                  snapshot.exists &&
                  data != null &&
                  data['isArchived'] != true &&
                  data['isSuspended'] != true;
              _productUnavailable = !available;
              if (snapshot.exists &&
                  data != null &&
                  data['isArchived'] != true &&
                  data['isSuspended'] != true) {
                _currentData = Map<String, dynamic>.from(data);
              }
            });
          },
          onError: (_) {
            if (mounted) setState(() => _productLoadError = true);
          },
        );
  }

  @override
  void dispose() {
    _productSub?.cancel();
    super.dispose();
  }

  String? _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('MMM d, y - h:mm a').format(ts.toDate());
    }
    return null;
  }

  Future<void> _reportReview(
    String reviewId,
    Map<String, dynamic> review,
    String productName,
  ) async {
    final reporter = FirebaseAuth.instance.currentUser;
    final sellerId = _currentData['farmerId']?.toString() ?? '';
    final reviewedBuyerId = review['buyerId']?.toString() ?? '';
    if (reporter == null || sellerId.isEmpty || reviewedBuyerId.isEmpty) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report this review?'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Tell us what is wrong with this review.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    final description = controller.text.trim();
    controller.dispose();
    if (confirmed != true || description.isEmpty || !mounted) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'issueType': 'Review Report',
        'description': description,
        'reporterId': reporter.uid,
        'reporterName': reporter.displayName ?? 'User',
        'reportedUserId': reviewedBuyerId,
        'reportedUserName': (review['buyerName'] ?? 'Buyer').toString(),
        'targetType': 'review',
        'farmerId': sellerId,
        'productId': widget.productId,
        'productName': productName,
        'reviewId': reviewId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review reported for admin review.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not report this review.')),
      );
    }
  }

  Widget _productImage() {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Image.network(
        _imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(color: _dark)),
        errorBuilder: (context, error, stackTrace) => Container(
          color: _accent,
          child: const Icon(Icons.broken_image, size: 90, color: _dark),
        ),
      );
    }
    return Container(
      color: _accent,
      child: const Icon(Icons.eco_rounded, size: 90, color: _dark),
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchFarmerProfile(
    String? farmerId,
  ) async {
    if (farmerId == null || farmerId.isEmpty) return null;
    try {
      return await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(farmerId)
          .get();
    } catch (_) {
      return null;
    }
  }

  Future<
    ({
      String area,
      double? buyerLat,
      double? buyerLng,
      double? centerLat,
      double? centerLng,
    })
  >
  _loadApproximateFarmerLocation(String? farmerId) async {
    if (farmerId == null || farmerId.isEmpty) {
      return (
        area: 'Farm area unavailable',
        buyerLat: null,
        buyerLng: null,
        centerLat: null,
        centerLng: null,
      );
    }
    final buyerId = FirebaseAuth.instance.currentUser?.uid;
    final farmerSnapshot = await FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(farmerId)
        .get();
    final farmer = farmerSnapshot.data() ?? const <String, dynamic>{};
    final barangay = (farmer['barangay'] ?? '').toString();
    final area = [barangay, farmer['municipality'], farmer['province']]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(', ');

    DocumentSnapshot<Map<String, dynamic>>? buyerGeo;
    if (buyerId != null && buyerId.isNotEmpty) {
      buyerGeo = await FirebaseFirestore.instance
          .collection('users')
          .doc(buyerId)
          .collection('private')
          .doc('geo')
          .get();
    }
    DocumentSnapshot<Map<String, dynamic>>? cluster;
    if (barangay.isNotEmpty) {
      cluster = await FirebaseFirestore.instance
          .collection('barangayClusters')
          .doc(barangay)
          .get();
    }

    final buyerData = buyerGeo?.data() ?? const <String, dynamic>{};
    final centerData = cluster?.data() ?? const <String, dynamic>{};
    return (
      area: area.isEmpty ? 'Farm area unavailable' : area,
      buyerLat: (buyerData['latitude'] as num?)?.toDouble(),
      buyerLng: (buyerData['longitude'] as num?)?.toDouble(),
      centerLat: (centerData['lat'] as num?)?.toDouble(),
      centerLng: (centerData['lng'] as num?)?.toDouble(),
    );
  }

  Widget _approximateFarmerMap(String? farmerId) {
    return FutureBuilder<
      ({
        String area,
        double? buyerLat,
        double? buyerLng,
        double? centerLat,
        double? centerLng,
      })
    >(
      future: _loadApproximateFarmerLocation(farmerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: _dark)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Text('Approximate farm area is unavailable.');
        }
        final location = snapshot.data!;
        final hasBuyer = location.buyerLat != null && location.buyerLng != null;
        final hasCenter =
            location.centerLat != null && location.centerLng != null;
        final distanceKm = hasBuyer && hasCenter
            ? Geolocator.distanceBetween(
                    location.buyerLat!,
                    location.buyerLng!,
                    location.centerLat!,
                    location.centerLng!,
                  ) /
                  1000
            : null;

        if (!hasCenter) {
          return Text(
            'Farm area: ${location.area}\nApproximate map is unavailable.',
          );
        }
        final center = LatLng(location.centerLat!, location.centerLng!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Farm area: ${location.area}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: 12,
                  ),
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('farmer_area'),
                      position: center,
                      infoWindow: const InfoWindow(
                        title: 'Approximate farm area',
                      ),
                    ),
                    if (hasBuyer)
                      Marker(
                        markerId: const MarkerId('buyer'),
                        position: LatLng(
                          location.buyerLat!,
                          location.buyerLng!,
                        ),
                        infoWindow: const InfoWindow(
                          title: 'Your saved location',
                        ),
                      ),
                  },
                  circles: {
                    Circle(
                      circleId: const CircleId('approximate_farmer_area'),
                      center: center,
                      radius: 450,
                      fillColor: _dark.withValues(alpha: 0.12),
                      strokeColor: _dark.withValues(alpha: 0.6),
                      strokeWidth: 1,
                    ),
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              distanceKm == null
                  ? 'Distance unavailable. Add a saved location to see an estimate.'
                  : 'About ${distanceKm.toStringAsFixed(1)} km away (approximate)',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshData() async {
    _watchProduct();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _productLoadError = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = _currentData;
    final name = data['name']?.toString() ?? 'Unnamed';
    final category = data['category']?.toString() ?? '';
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final wholesaleMinimum = (data['wholesaleMinimumQuantity'] as num?) ?? 1;
    final wholesaleEnabled =
        data['wholesaleEnabled'] == true ||
        (data['wholesaleEnabled'] == null &&
            wholesalePrice != null &&
            wholesalePrice > 0);
    final available = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final description = data['description']?.toString() ?? '';
    final farmerName = data['farmerName']?.toString() ?? 'Farmer';
    final farmerId = data['farmerId']?.toString();
    final delivery = data['deliveryAvailable'] == true;
    final pickup = data['pickupOnly'] == true;
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = (data['reviewCount'] as num?)?.toInt();
    final postedOn = _formatDate(data['createdAt']);
    final updatedOn = _formatDate(data['updatedAt']);

    if (_productLoadError || _productUnavailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product Details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _productLoadError
                      ? 'Could not load this product. Check your connection and try again.'
                      : 'This listing is no longer available.',
                  textAlign: TextAlign.center,
                ),
                if (_productLoadError) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _refreshData,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Product Details'),
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: _dark,
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: _productImage(),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              color: _dark,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          formatPeso(price),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: _dark,
                          ),
                        ),
                        Text(
                          'per $unit',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (wholesaleEnabled &&
                        wholesalePrice != null &&
                        wholesalePrice > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wholesale available',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _dark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatPriceWithUnit(wholesalePrice, unit)} for orders of '
                              '${formatStock(wholesaleMinimum, unit)} or more',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey[700],
                              ),
                            ),
                            if (available < wholesaleMinimum) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Wholesale is temporarily unavailable because current stock is below the minimum.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (rating != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          if (reviewCount != null)
                            Text(
                              '($reviewCount Reviews)',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    if (postedOn != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Posted on $postedOn',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                    if (updatedOn != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Updated on $updatedOn',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          FutureBuilder<
                            DocumentSnapshot<Map<String, dynamic>>?
                          >(
                            future: _fetchFarmerProfile(farmerId),
                            builder: (context, snapshot) {
                              final farmerData = snapshot.data?.data();
                              final photoUrl =
                                  farmerData?['photoUrl']?.toString() ?? '';

                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: _dark,
                                    ),
                                  ),
                                );
                              }

                              return Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  image: (photoUrl.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(photoUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: photoUrl.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: _dark,
                                        size: 24,
                                      )
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  farmerName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Farmer',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.verified, color: _dark, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    color: _dark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _approximateFarmerMap(farmerId),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: infoRow(
                            Icons.inventory_2,
                            available > 0
                                ? '${formatStock(available, unit)} available'
                                : 'Out of stock',
                          ),
                        ),
                        if (available <= 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Text(
                              'OUT OF STOCK',
                              style: TextStyle(
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (delivery || pickup) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (delivery) tag(Icons.local_shipping, 'Delivery'),
                          if (pickup) tag(Icons.storefront, 'Pick-up'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.description, size: 18, color: _dark),
                        SizedBox(width: 6),
                        Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description.isEmpty
                          ? 'No description provided.'
                          : description,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reviews',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('productReviews')
                          .where('productId', isEqualTo: widget.productId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: _dark),
                          );
                        }
                        if (snapshot.hasError) {
                          return Text(
                            'Could not load reviews.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          );
                        }

                        final docs =
                            List<
                                QueryDocumentSnapshot<Map<String, dynamic>>
                              >.from(
                                snapshot.data?.docs ??
                                    const <
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >[],
                              )
                              ..removeWhere(
                                (doc) =>
                                    doc.data()['moderationStatus'] == 'removed',
                              )
                              ..sort((a, b) {
                                final at = a.data()['createdAt'] as Timestamp?;
                                final bt = b.data()['createdAt'] as Timestamp?;
                                final ams = at?.millisecondsSinceEpoch ?? 0;
                                final bms = bt?.millisecondsSinceEpoch ?? 0;
                                return bms.compareTo(ams);
                              });

                        if (docs.isEmpty) {
                          return Text(
                            'No reviews yet.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final review = doc.data();
                            final reviewer =
                                review['buyerName']?.toString() ?? 'Buyer';
                            final reviewerId =
                                review['buyerId']?.toString() ?? '';
                            final reviewText =
                                review['comment']?.toString() ?? '';
                            final reviewRating =
                                (review['rating'] as num?)?.toDouble() ?? 0;
                            final reviewImage =
                                review['imageUrl']?.toString() ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          reviewer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        children: List.generate(
                                          5,
                                          (index) => Icon(
                                            reviewRating >= index + 1
                                                ? Icons.star_rounded
                                                : reviewRating >= index + 0.5
                                                ? Icons.star_half_rounded
                                                : Icons.star_border_rounded,
                                            size: 14,
                                            color: reviewRating >= index + 0.5
                                                ? Colors.amber
                                                : Colors.grey[400],
                                          ),
                                        ),
                                      ),
                                      if (FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid !=
                                              reviewerId &&
                                          FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid !=
                                              farmerId)
                                        IconButton(
                                          tooltip: 'Report review',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _reportReview(
                                            doc.id,
                                            review,
                                            name,
                                          ),
                                          icon: const Icon(
                                            Icons.flag_outlined,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (reviewText.isNotEmpty)
                                    Text(
                                      reviewText,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  if (reviewImage.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        reviewImage,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          height: 100,
                                          color: _accent,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.broken_image,
                                            color: _dark,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid !=
                                            reviewerId &&
                                        FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid !=
                                            farmerId)
                                      IconButton(
                                        tooltip: 'Report review',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _reportReview(doc.id, review, name),
                                        icon: const Icon(
                                          Icons.flag_outlined,
                                          size: 18,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _actionButton(
                  available > 0 ? Icons.shopping_bag_outlined : Icons.block,
                  available > 0 ? 'Order Now' : 'Out of Stock',
                  available <= 0 || farmerId == null || farmerId.isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaceOrderScreen(
                              sellerId: farmerId,
                              sellerName: farmerName,
                              productId: widget.productId,
                              productName: name,
                              productPrice: formatPriceWithUnit(price, unit),
                              productImage: _imageUrl ?? '',
                              deliveryAvailable: delivery,
                              pickupAvailable: pickup,
                              unit: unit,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: available <= 0 || farmerId == null || farmerId.isEmpty
                    ? null
                    : () => _messageFarmer(farmerId, farmerName, name),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.message_outlined,
                    color: _dark,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BuyerMapView()),
                ),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.map, color: _dark, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _messageFarmer(
    String farmerId,
    String farmerName,
    String productName,
  ) async {
    if (!mounted) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (currentUserId.isEmpty || farmerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to message this farmer. Try again later.'),
        ),
      );
      return;
    }

    final messageService = MessageService();
    final conversationId = messageService.conversationIdFor(
      currentUserId,
      farmerId,
    );

    try {
      await messageService.startOrGetConversation(
        otherUserId: farmerId,
        otherUserName: farmerName,
        productId: widget.productId,
        productName: productName,
        productImageUrl: _imageUrl ?? '',
        retailPrice:
            (widget.data['retailPrice'] as num?) ??
            (widget.data['price'] as num?) ??
            0,
        wholesalePrice: widget.data['wholesalePrice'] as num?,
        wholesaleMinimumQuantity:
            (widget.data['wholesaleMinimumQuantity'] as num?)?.toInt() ?? 1,
        retailMaximumQuantity:
            (widget.data['retailMaximumQuantity'] as num?)?.toInt() ?? 1,
        unit:
            (widget.data['unit'] as String?) ?? unitForProductName(productName),
        deliveryAvailable: widget.data['deliveryAvailable'] == true,
        pickupOnly: widget.data['pickupOnly'] == true,
      );
    } catch (_) {
      // Swallow chat creation errors and continue to the chat view.
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageOrderScreen(
          conversationId: conversationId,
          farmerId: farmerId,
          productId: widget.productId,
          farmerName: farmerName,
          productName: productName,
          productPrice: formatPriceWithUnit(
            (widget.data['retailPrice'] as num?) ??
                (widget.data['price'] as num?) ??
                0,
            (widget.data['unit'] as String?) ?? unitForProductName(productName),
          ),
          productImage: _imageUrl ?? '',
          deliveryAvailable: widget.data['deliveryAvailable'] == true,
          pickupAvailable: widget.data['pickupOnly'] == true,
          unit:
              (widget.data['unit'] as String?) ??
              unitForProductName(productName),
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: disabled ? Colors.grey[300] : _accent,
        foregroundColor: disabled ? Colors.grey[600] : _dark,
        disabledBackgroundColor: Colors.grey[300],
        disabledForegroundColor: Colors.grey[600],
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: disabled ? Colors.grey[600] : _dark, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: disabled ? Colors.grey[600] : _dark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _dark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget tag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget circleButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _dark),
      ),
    );
  }
}
