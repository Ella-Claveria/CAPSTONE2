import '../widgets/agri_app_bar.dart';
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
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/app_back_button.dart';
import '../widgets/save_product_button.dart';
import '../data/commodity_master_list.dart';
import 'message_order_screen.dart';
import 'place_order_screen.dart';
import 'product_reviews_screen.dart';
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
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              distanceKm == null
                  ? 'Distance unavailable. Add a saved location to see an estimate.'
                  : 'Approx. ${distanceKm.toStringAsFixed(1)} km away',
              style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
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
              'The marker shows the general barangay area, not the exact '
              'farm.',
              style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
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
          // The content panel's rounded top edge, drawn over the foot of
          // the image so the photo curves into the white panel below.
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: 27,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
            ),
          ),
          if (!single)
            Positioned(
              bottom: 38,
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
                    // Back is not in this row: it floats above the whole
                    // page (see build) so it stays put while this scrolls.
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

  // The thin rule between sections of the content panel.
  Widget _divider({double top = 18, double bottom = 18}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: bottom),
    child: Divider(height: 1, thickness: 1, color: Colors.grey[200]),
  );

  // One line of the product summary: icon, text, optional trailing note.
  Widget _infoRow(IconData icon, String text, {Widget? trailing}) => Row(
    children: [
      Icon(icon, size: 16, color: Colors.grey[600]),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13.5, color: Colors.grey[800]),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _sectionTitle(String text) => Text(text, style: AppTheme.heading(17));

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

        // A plain row between two dividers, not a card: the whole row is
        // the tap target.
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ProfileAvatar(
                    photoUrl: farmer?['photoUrl']?.toString(),
                    name: displayName,
                    radius: 23,
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
          padding: const EdgeInsets.only(top: 8),
          child: _infoRow(Icons.place_outlined, area),
        );
      },
    );
  }

  static const int _reviewsPreviewed = 6;

  // A short preview of this exact product's reviews, newest first: the
  // rating summary, "View All", then a row of compact cards to swipe
  // through. The full text, photos and replies are on ProductReviewsScreen.
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
                style: TextStyle(color: Colors.grey[700], fontSize: 13.5),
              ),
            ],
          );
        }

        final docs = visibleProductReviews(snapshot.data);

        // No rating summary at all — a "0.0" would read as a bad score.
        if (docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Buyer Reviews'),
              const SizedBox(height: 10),
              const Text(
                'No reviews yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Be the first to review this product after completing an '
                'order.',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          );
        }

        final average = averageReviewRating(docs);
        final shown = docs.take(_reviewsPreviewed).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Buyer Reviews'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            average.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            docs.length == 1
                                ? '(1 review)'
                                : '(${docs.length} reviews)',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductReviewsScreen(
                        productId: widget.productId,
                        productName: productName,
                        farmerId: farmerId,
                      ),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _dark,
                    padding: const EdgeInsets.only(left: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All (${docs.length})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bleeds to both screen edges so cards slide under the page
            // padding instead of being cut off at it.
            SizedBox(
              height: 148,
              child: OverflowBox(
                maxWidth: MediaQuery.sizeOf(context).width,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) =>
                      _reviewPreviewCard(shown[index].data()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Compact on purpose: name, stars, date and a few lines of the text. No
  // photos here — those are on the full reviews screen.
  Widget _reviewPreviewCard(Map<String, dynamic> review) {
    final reviewer = review['buyerName']?.toString() ?? 'Buyer';
    final text = review['comment']?.toString() ?? '';
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final created = (review['createdAt'] as Timestamp?)?.toDate();

    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Initials only — a review shows the buyer's name, not their
              // profile.
              ProfileAvatar(photoUrl: null, name: reviewer, radius: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ReviewStars(rating: rating, size: 13),
                        if (created != null) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, y').format(created),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
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
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              text.isEmpty ? 'No written review.' : text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: text.isEmpty ? Colors.grey[600] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _currentData;

    if (_productLoadError || _productUnavailable) {
      return Scaffold(
        appBar: const AgriAppBar(title: 'Product Details'),
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _content(context, data)),
          // Stays at the upper-left however far the page is scrolled.
          const Positioned(
            top: 0,
            left: 12,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                // Over the product photo, so the circle stays on.
                child: AppBackButton(overImage: true),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(data),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> data) {
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
    final hasWholesale =
        wholesaleEnabled && wholesalePrice != null && wholesalePrice > 0;
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

    return AgriRefreshIndicator(
      color: _dark,
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _gallery(data),

            // One continuous white panel under the image: sections are
            // set apart by spacing and thin dividers, not separate cards.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Name, price, stock, location, selling terms ----
                  if (category.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F7EC),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    name,
                    style: AppTheme.heading(26).copyWith(height: 1.15),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        formatPeso(price),
                        style: AppTheme.heading(
                          32,
                        ).copyWith(color: _dark, height: 1.1),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '/ $unit',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Only once the product actually has reviews.
                  if (rating != null && reviewCount > 0) ...[
                    const SizedBox(height: 8),
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
                  const SizedBox(height: 14),
                  _infoRow(
                    Icons.inventory_2_outlined,
                    available > 0
                        ? '${formatStock(available, unit)} available'
                        : 'Out of stock',
                    trailing: available > 0
                        ? null
                        : Container(
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
                  ),
                  _farmerAreaLine(),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.sell_outlined,
                    hasWholesale ? 'Retail and wholesale' : 'Retail only',
                  ),
                  // Fulfillment, as one plain line with the rest of the
                  // summary rather than standalone chips.
                  if (delivery || pickup) ...[
                    const SizedBox(height: 8),
                    _infoRow(
                      Icons.local_shipping_outlined,
                      delivery && pickup
                          ? 'Delivery and pick-up'
                          : delivery
                          ? 'Delivery'
                          : 'Pick-up',
                    ),
                  ],
                  if (harvested != null) ...[
                    const SizedBox(height: 8),
                    _infoRow(
                      Icons.eco_outlined,
                      harvestLabel(harvested),
                      trailing: isRecentlyHarvested(harvested)
                          ? const Text(
                              'Recently Harvested',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _dark,
                              ),
                            )
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 2),
                      child: Text(
                        [
                          if (data['updatedAt'] is Timestamp)
                            'Last updated ${DateFormat('MMM d, y').format((data['updatedAt'] as Timestamp).toDate())}.',
                          'Harvest information is provided and updated by the farmer.',
                        ].join(' '),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ],

                  // ---- Wholesale: one quiet light-green note ----
                  if (hasWholesale) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F7EC),
                        borderRadius: BorderRadius.circular(14),
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
                          const SizedBox(height: 3),
                          Text(
                            '${formatPriceWithUnit(wholesalePrice, unit)} for orders of '
                            '${formatStock(wholesaleMinimum, unit)} or more',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[800],
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

                  // ---- Farmer ----
                  _divider(top: 18, bottom: 4),
                  _farmerRow(farmerId, farmerName),
                  _divider(top: 4),

                  // ---- Description ----
                  _sectionTitle('Description'),
                  const SizedBox(height: 8),
                  Text(
                    description.isEmpty
                        ? 'No description provided.'
                        : description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.55,
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

                  // ---- Reviews for this product ----
                  _divider(),
                  _reviewsSection(name, farmerId),

                  // ---- Approximate farm area (never the exact pin) ----
                  _divider(),
                  Row(
                    children: [
                      Expanded(child: _sectionTitle('Farm Location')),
                      // The approximate-area map, full screen.
                      if (farmerId != null && farmerId.isNotEmpty)
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BuyerMapView(
                                farmerId: farmerId,
                                farmerName: farmerName,
                              ),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _dark,
                            padding: const EdgeInsets.only(left: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open Map',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _approximateFarmerMap(farmerId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Message to Order (primary) | Order Now ----
  // No Map here: the Farm Location section above has Open Map.
  // Sticky: it is the Scaffold's bottom bar, so it never scrolls away.
  Widget _bottomBar(Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? 'Unnamed';
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final available = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final farmerName = data['farmerName']?.toString() ?? 'Farmer';
    final farmerId = data['farmerId']?.toString();
    final delivery = data['deliveryAvailable'] == true;
    final pickup = data['pickupOnly'] == true;
    final canContact = farmerId != null && farmerId.isNotEmpty;
    final canOrder = available > 0 && canContact;

    return SafeArea(
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
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canOrder
                    ? () => _messageFarmer(farmerId, farmerName, name)
                    : null,
                icon: Icon(
                  available > 0 ? Icons.chat_bubble_outline : Icons.block,
                  size: 18,
                ),
                label: Text(
                  available > 0 ? 'Message to Order' : 'Out of Stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
                  elevation: 0,
                  minimumSize: const Size.fromHeight(_actionHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_actionHeight / 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _iconAction(
              icon: Icons.shopping_bag_outlined,
              tooltip: 'Order Now',
              onTap: !canOrder
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
          ],
        ),
      ),
    );
  }

  // One height for every action on this screen; the buttons are pills and
  // circles of it.
  static const double _actionHeight = 50;

  // A small icon-only action: light green fill, thin green outline.
  Widget _iconAction({
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
          backgroundColor: enabled
              ? const Color(0xFFF1F7EC)
              : Colors.grey.shade100,
          side: BorderSide(
            color: enabled
                ? _dark.withValues(alpha: 0.35)
                : Colors.grey.shade300,
          ),
          minimumSize: const Size(_actionHeight, _actionHeight),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
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
