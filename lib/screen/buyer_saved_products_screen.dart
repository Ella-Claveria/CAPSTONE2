import '../widgets/agri_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/saved_products_service.dart';
import '../theme/app_theme.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/retry_message.dart';
import '../widgets/save_product_button.dart';
import 'product_detail_screen.dart';
import '../widgets/agri_empty_state.dart';

/// The listings this buyer liked on Explore or Product Details (the heart
/// icon in its app bar) — the same cards as the Explore grid, read live.
class BuyerSavedProductsScreen extends StatefulWidget {
  const BuyerSavedProductsScreen({super.key});

  @override
  State<BuyerSavedProductsScreen> createState() =>
      _BuyerSavedProductsScreenState();
}

class _BuyerSavedProductsScreenState extends State<BuyerSavedProductsScreen> {
  static const Color _dark = AppTheme.dark;

  final _service = SavedProductsService();
  final _likes = LikedProducts.instance;

  // Listings already fetched, by product id (null = no longer available).
  // Kept so that unliking one card doesn't reload the whole grid.
  final Map<String, DocumentSnapshot<Map<String, dynamic>>?> _products = {};
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _likes
      ..start()
      ..addListener(_onLikesChanged);
    _loadMissing();
  }

  @override
  void dispose() {
    _likes.removeListener(_onLikesChanged);
    super.dispose();
  }

  void _onLikesChanged() {
    if (!mounted) return;
    setState(() {});
    _loadMissing();
  }

  Future<void> _loadMissing() async {
    final missing = [
      for (final id in _likes.orderedIds)
        if (!_products.containsKey(id)) id,
    ];
    if (missing.isEmpty) return;
    try {
      final found = await _service.loadProducts(missing);
      if (!mounted) return;
      setState(() {
        _loadFailed = false;
        for (final id in missing) {
          _products[id] = null;
        }
        for (final doc in found) {
          _products[doc.id] = doc;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _likes.orderedIds;
    final loading =
        !_likes.loaded || ids.any((id) => !_products.containsKey(id));
    final products = [
      for (final id in ids)
        if (_products[id] != null) _products[id]!,
    ];

    final Widget body;
    if (_loadFailed && products.isEmpty) {
      body = RetryMessage(
        message:
            'Could not load your liked products. Check your connection and try again.',
        onRetry: _loadMissing,
      );
    } else if (products.isNotEmpty) {
      body = _grid(products);
    } else if (loading) {
      body = const Center(child: CircularProgressIndicator(color: _dark));
    } else {
      body = _empty(unavailable: ids.isNotEmpty);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buyerSubScreenAppBar('Liked Products'),
      body: body,
    );
  }

  Widget _grid(List<DocumentSnapshot<Map<String, dynamic>>> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 12.0;
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - padding * 2 - spacing) / 2;
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: ExploreProductCard.extentFor(
              cardWidth,
              MediaQuery.textScalerOf(context),
            ),
          ),
          itemBuilder: (context, index) {
            final doc = products[index];
            final data = doc.data()!;
            return ExploreProductCard(
              data: data,
              saved: true,
              // Unliking it here drops it from this list (and from every
              // other heart in the app).
              onToggleSave: () => toggleLikedProduct(context, doc.id),
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

  Widget _empty({bool unavailable = false}) {
    return Center(
      child: AgriEmptyState(
        icon: Icons.favorite_border_rounded,
        title: unavailable
            ? 'Your liked products are no longer available'
            : 'No liked products yet',
        subtitle: 'Tap the heart on a product to keep it here for later.',
        padding: const EdgeInsets.all(32),
      ),
    );
  }
}

/// The app bar shared by the screens opened from the Buyer Profile.
PreferredSizeWidget buyerSubScreenAppBar(String title) =>
    AgriAppBar(title: title);
