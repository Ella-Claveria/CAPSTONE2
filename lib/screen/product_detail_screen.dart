import '../theme/app_theme.dart';
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
import '../services/product_share_service.dart';
import '../services/public_farm_location.dart';
import '../services/harvest_info.dart';
import '../services/market_price_helpers.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/save_product_button.dart';
import '../data/commodity_master_list.dart';
import 'message_order_screen.dart';
import 'place_order_screen.dart';
import 'buyer_market_view.dart';
import 'farmer_storefront_screen.dart';
import '../widgets/profile_avatar.dart';

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
  static const Color _dark = AppTheme.dark;
  static const Color _accent = Color(0xFFDCEDC8);

  Uint8List? _imageBytes;
  String? _imageUrl;
  late Map<String, dynamic> _currentData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _productSub;

  late final Future<DocumentSnapshot<Map<String, dynamic>>?> _farmerProfile;
  late final Future<
    ({
      String area,
      double? buyerLat,
      double? buyerLng,
      double? centerLat,
      double? centerLng,
    })
  >
  _farmerLocation;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _reviews =
      FirebaseFirestore.instance
          .collection('productReviews')
          .where('productId', isEqualTo: widget.productId)
          .snapshots();
  final ValueNotifier<int> _galleryPage = ValueNotifier(0);
  bool _showAllReviews = false;
  bool _productUnavailable = false;
  bool _productLoadError = false;

  @override
  void initState() {
    super.initState();
    _currentData = Map<String, dynamic>.from(widget.data);
    _watchProduct();
    ProductService().logProductView(widget.productId);

    // Loaded once — not from build(), where every rebuild (a new gallery
    // page, expanding the reviews) would fetch the farmer again and reload
    // the map.
    final farmerId = widget.data['farmerId']?.toString();
    _farmerProfile = _fetchFarmerProfile(farmerId);
    _farmerLocation = _loadApproximateFarmerLocation(farmerId);

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
    _galleryPage.dispose();
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
    final confirmed = await showAgriDialog<bool>(
      context: context,
      builder: (dialogContext) => AgriDialog(
        icon: Icons.flag_outlined,
        tone: AgriTone.warning,
        title: const Text('Report this review?'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Tell us what is wrong with this review.',
          ),
        ),
        actions: [
          AgriDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AgriDialogButton(
            label: 'Report',
            kind: AgriButtonKind.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
    // The farmer's public, barangay-level location only (see
    // public_farm_location.dart) — the same source the Farm Location map
    // uses, so both show the same stable area and neither can reveal a
    // farm's exact pin.
    final farm = await loadPublicFarmLocation(farmerId);

    DocumentSnapshot<Map<String, dynamic>>? buyerGeo;
    if (buyerId != null && buyerId.isNotEmpty) {
      buyerGeo = await FirebaseFirestore.instance
          .collection('users')
          .doc(buyerId)
          .collection('private')
          .doc('geo')
          .get();
    }

    final buyerData = buyerGeo?.data() ?? const <String, dynamic>{};
    // A saved position outside the Philippines (e.g. captured from an
    // emulator's default location) is not used: it would show a distance
    // of thousands of kilometres.
    final savedLat = (buyerData['latitude'] as num?)?.toDouble();
    final savedLng = (buyerData['longitude'] as num?)?.toDouble();
    final buyerOk = isValidPublicCoordinate(savedLat, savedLng);
    return (
      area: farm.area.isEmpty ? 'Farm area unavailable' : farm.area,
      buyerLat: buyerOk ? savedLat : null,
      buyerLng: buyerOk ? savedLng : null,
      centerLat: farm.latitude,
      centerLng: farm.longitude,
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
      // Cached (see initState): a rebuild must not reload the map.
      future: _farmerLocation,
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
                      radius: 700,
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

  // ---- Image gallery with the back / heart / share buttons on top ----
  List<String> get _galleryUrls {
    final urls = <String>[
      if (_currentData['imageUrls'] is List)
        for (final url in _currentData['imageUrls'] as List)
          if (url != null && url.toString().isNotEmpty) url.toString(),
    ];
    if (urls.isEmpty && _imageUrl != null && _imageUrl!.isNotEmpty) {
      urls.add(_imageUrl!);
    }
    return urls;
  }

  Widget _networkImage(String url) => Image.network(
    url,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator(color: _dark)),
    errorBuilder: (context, error, stackTrace) => Container(
      color: _accent,
      child: const Icon(Icons.broken_image, size: 90, color: _dark),
    ),
  );

  Widget _gallery(Map<String, dynamic> data) {
    final urls = _galleryUrls;
    // A stored (base64) photo, or no photo at all, is a single image.
    final single = _imageBytes != null || urls.length <= 1;

    return AspectRatio(
      aspectRatio: 1.15,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (single)
            _productImage()
          else
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (page) => _galleryPage.value = page,
              itemBuilder: (context, index) => _networkImage(urls[index]),
            ),
          if (!single)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: _galleryPage,
                builder: (context, page, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < urls.length; i++)
                      Container(
                        width: i == page ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: i == page ? 1 : 0.6,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    circleButton(
                      Icons.arrow_back,
                      () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    // The heart — buyers only (it draws nothing otherwise).
                    SaveProductButton(productId: widget.productId),
                    const SizedBox(width: 10),
                    Builder(
                      builder: (buttonContext) => circleButton(
                        Icons.share_outlined,
                        () => ProductShareService.share(
                          buttonContext,
                          widget.productId,
                          data,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionTitle(String text) => Text(text, style: AppTheme.heading(16));

  // Compact farmer row — opens that farmer's public profile. Photo and
  // Verified status come from the public profile, never assumed.
  Widget _farmerRow(String? farmerId, String farmerName) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _farmerProfile,
      builder: (context, snapshot) {
        final farmer = snapshot.data?.data();
        final verified = farmer?['approvalStatus'] == 'approved';
        final displayName =
            (farmer?['name'] ?? farmer?['fullName'] ?? farmerName).toString();

        return Material(
          color: const Color(0xFFF4F7F4),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: farmerId == null || farmerId.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FarmerStorefrontScreen(farmerId: farmerId),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  ProfileAvatar(
                    photoUrl: farmer?['photoUrl']?.toString(),
                    name: displayName,
                    radius: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (verified)
                          const Row(
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: _dark,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Verified Farmer',
                                style: TextStyle(
                                  color: _dark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            'Farmer',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[600]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Farmer's general area (barangay, municipality) under the price.
  Widget _farmerAreaLine() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _farmerProfile,
      builder: (context, snapshot) {
        final farmer = snapshot.data?.data();
        final area = [farmer?['barangay'], farmer?['municipality']]
            .map((v) => (v ?? '').toString().trim())
            .where((v) => v.isNotEmpty)
            .join(', ');
        if (area.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const int _reviewsShownAtFirst = 3;

  // Reviews for this exact product, newest first.
  Widget _reviewsSection(String productName, String? farmerId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Buyer Reviews'),
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator(color: _dark)),
            ],
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Buyer Reviews'),
              const SizedBox(height: 8),
              Text(
                'Could not load reviews.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13.5),
              ),
            ],
          );
        }

        final docs =
            (snapshot.data?.docs ?? const [])
                .where((doc) => doc.data()['moderationStatus'] != 'removed')
                .toList()
              ..sort((a, b) {
                final at = a.data()['createdAt'] as Timestamp?;
                final bt = b.data()['createdAt'] as Timestamp?;
                return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                  at?.millisecondsSinceEpoch ?? 0,
                );
              });

        if (docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Buyer Reviews'),
              const SizedBox(height: 14),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 34,
                      color: Colors.grey[350],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No reviews yet',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          );
        }

        final average =
            docs
                .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            docs.length;
        final shown = _showAllReviews
            ? docs
            : docs.take(_reviewsShownAtFirst).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionTitle('Buyer Reviews (${docs.length})'),
                ),
                const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                const SizedBox(width: 3),
                Text(
                  average.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 22, color: Colors.grey[200]),
              _reviewCard(shown[i], productName, farmerId),
            ],
            if (docs.length > _reviewsShownAtFirst)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _showAllReviews = !_showAllReviews),
                  style: TextButton.styleFrom(foregroundColor: _dark),
                  child: Text(
                    _showAllReviews ? 'Show Less' : 'View All (${docs.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _reviewCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String productName,
    String? farmerId,
  ) {
    final review = doc.data();
    final reviewer = review['buyerName']?.toString() ?? 'Buyer';
    final reviewerId = review['buyerId']?.toString() ?? '';
    final reviewText = review['comment']?.toString() ?? '';
    final reviewRating = (review['rating'] as num?)?.toDouble() ?? 0;
    final reviewImage = review['imageUrl']?.toString() ?? '';
    final created = (review['createdAt'] as Timestamp?)?.toDate();
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final canReport = viewerId != reviewerId && viewerId != farmerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Initials only — a review shows the buyer's name, not their
            // profile.
            ProfileAvatar(photoUrl: null, name: reviewer, radius: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reviewer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                      if (created != null)
                        Text(
                          DateFormat('MMM d, y').format(created),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (canReport)
              IconButton(
                tooltip: 'Report review',
                visualDensity: VisualDensity.compact,
                onPressed: () => _reportReview(doc.id, review, productName),
                icon: Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        // Every review is tied to the buyer's own completed order (see
        // firestore.rules).
        if ((review['orderId'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.verified_outlined, size: 13, color: _dark),
              SizedBox(width: 4),
              Text(
                'Verified Purchase',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _dark,
                ),
              ),
            ],
          ),
        ],
        if (reviewText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            reviewText,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
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
                child: const Icon(Icons.broken_image, color: _dark),
              ),
            ),
          ),
        ],
      ],
    );
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
    final reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
    final postedOn = _formatDate(data['createdAt']);
    final updatedOn = _formatDate(data['updatedAt']);
    final harvested = harvestDateOf(data);
    final canContact = farmerId != null && farmerId.isNotEmpty;

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
      backgroundColor: const Color(0xFFF7F9F6),
      body: AgriRefreshIndicator(
        color: _dark,
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gallery(data),
              const SizedBox(height: 14),

              // ---- Name, price, stock, location, wholesale ----
              _section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category.isNotEmpty) ...[
                      Text(
                        category.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(name, style: AppTheme.heading(22)),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          formatPeso(price),
                          style: AppTheme.heading(28).copyWith(color: _dark),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'per $unit',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Only once the product actually has reviews.
                    if (rating != null && reviewCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            reviewCount == 1
                                ? '(1 review)'
                                : '($reviewCount reviews)',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            available > 0
                                ? '${formatStock(available, unit)} available'
                                : 'Out of stock',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
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
                    _farmerAreaLine(),
                    if (delivery || pickup) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (delivery) tag(Icons.local_shipping, 'Delivery'),
                          if (pickup) tag(Icons.storefront, 'Pick-up'),
                        ],
                      ),
                    ],
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
                    if (harvested != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8EF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Harvest Information',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  harvestLabel(harvested),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (isRecentlyHarvested(harvested))
                                  const Text(
                                    'Recently Harvested',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _dark,
                                    ),
                                  ),
                              ],
                            ),
                            if (data['updatedAt'] is Timestamp)
                              Text(
                                'Last updated ${DateFormat('MMM d, y').format((data['updatedAt'] as Timestamp).toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              'Harvest information is provided and updated by the farmer.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _farmerRow(farmerId, farmerName),
                  ],
                ),
              ),

              // ---- Description ----
              _section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Description'),
                    const SizedBox(height: 8),
                    Text(
                      description.isEmpty
                          ? 'No description provided.'
                          : description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.black87,
                      ),
                    ),
                    if (postedOn != null || updatedOn != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          if (postedOn != null) 'Posted on $postedOn',
                          if (updatedOn != null) 'Updated on $updatedOn',
                        ].join('\n'),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ---- Reviews for this product ----
              _section(child: _reviewsSection(name, farmerId)),

              // ---- Approximate farm area (never the exact pin) ----
              _section(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Farm Location'),
                    const SizedBox(height: 8),
                    _approximateFarmerMap(farmerId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // ---- Order Now (primary) + Message + Map ----
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
              _outlinedAction(
                icon: Icons.message_outlined,
                tooltip: 'Message',
                onTap: available <= 0 || !canContact
                    ? null
                    : () => _messageFarmer(farmerId, farmerName, name),
              ),
              const SizedBox(width: 10),
              _outlinedAction(
                icon: Icons.map_outlined,
                tooltip: 'Map',
                onTap: !canContact
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BuyerMapView(
                            farmerId: farmerId,
                            farmerName: farmerName,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: available <= 0 || !canContact
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
                  icon: Icon(
                    available > 0 ? Icons.shopping_bag_outlined : Icons.block,
                    size: 18,
                  ),
                  label: Text(
                    available > 0 ? 'Order Now' : 'Out of Stock',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                    elevation: 0,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outlinedAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _dark,
          side: BorderSide(color: enabled ? _dark : Colors.grey.shade300),
          minimumSize: const Size(50, 50),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Icon(icon, size: 22),
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
