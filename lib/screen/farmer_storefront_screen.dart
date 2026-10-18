import '../widgets/agri_app_bar.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/saved_products_service.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/save_product_button.dart';
import 'product_detail_screen.dart';

/// A farmer's public profile, as a buyer sees it: photo, name, general
/// location and Verified Farmer badge, then their active listings in a
/// two-column grid. Everything comes from publicProfiles/{farmerId} (the
/// allow-listed projection — no email, phone or exact location) and the
/// farmer's own products.
///
/// There is no separate reviews list here: reviews belong to individual
/// products and are shown on each one's Product Details.
class FarmerStorefrontScreen extends StatefulWidget {
  final String farmerId;

  const FarmerStorefrontScreen({super.key, required this.farmerId});

  @override
  State<FarmerStorefrontScreen> createState() => _FarmerStorefrontScreenState();
}

class _FarmerStorefrontScreenState extends State<FarmerStorefrontScreen> {
  static const _green = AppTheme.dark;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(widget.farmerId)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _products =
      FirebaseFirestore.instance
          .collection('products')
          .where('farmerId', isEqualTo: widget.farmerId)
          .snapshots();

  // The heart on each card (buyers only) — the shared LikedProducts state,
  // the same one Explore, Search and Product Details use.
  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    LikedProducts.instance
      ..start()
      ..addListener(_onLikesChanged);
  }

  @override
  void dispose() {
    LikedProducts.instance.removeListener(_onLikesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AgriAppBar(),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          final profile = profileSnap.data?.data();
          if (profileSnap.hasError || profile == null) {
            return const Center(child: Text('Farmer profile is unavailable.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              _header(profile),
              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey[200]),
              const SizedBox(height: 16),
              _productsSection(),
            ],
          );
        },
      ),
    );
  }

  Widget _header(Map<String, dynamic> profile) {
    final name = (profile['name'] ?? profile['fullName'] ?? 'Farmer')
        .toString();
    // General area only — the public profile never holds an exact location.
    final location = [profile['barangay'], profile['municipality']]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .join(', ');
    final bio = (profile['bio'] ?? '').toString().trim();
    final verified = profile['approvalStatus'] == 'approved';

    return Column(
      children: [
        ProfileAvatar(
          photoUrl: profile['photoUrl']?.toString(),
          name: name,
          radius: 46,
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.heading(22),
        ),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.place_outlined, size: 15, color: Colors.grey[600]),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (verified) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.tint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 15, color: _green),
                SizedBox(width: 5),
                Text(
                  'Verified Farmer',
                  style: TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            bio,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.grey[700],
            ),
          ),
        ],
      ],
    );
  }

  Widget _productsSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _products,
      builder: (context, productSnap) {
        if (productSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: _green)),
          );
        }
        if (productSnap.hasError) {
          return _note('Could not load this farmer’s products.');
        }
        final products = (productSnap.data?.docs ?? const [])
            .where(
              (doc) =>
                  doc.data()['isArchived'] != true &&
                  doc.data()['isSuspended'] != true,
            )
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Products (${products.length})', style: AppTheme.heading(17)),
            const SizedBox(height: 12),
            if (products.isEmpty)
              _note('No active products right now.')
            else
              _grid(products),
          ],
        );
      },
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
  );

  Widget _grid(List<QueryDocumentSnapshot<Map<String, dynamic>>> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: ExploreProductCard.extentFor(
              cardWidth,
              MediaQuery.textScalerOf(context),
              showFarmer: false,
            ),
          ),
          itemBuilder: (context, index) {
            final doc = products[index];
            final data = doc.data();
            return ExploreProductCard(
              data: data,
              // Every card here is this farmer's — no need to repeat it.
              showFarmer: false,
              saved: LikedProducts.instance.contains(doc.id),
              onToggleSave: LikedProducts.instance.canLike
                  ? () => toggleLikedProduct(context, doc.id)
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProductDetailScreen(productId: doc.id, data: data),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
