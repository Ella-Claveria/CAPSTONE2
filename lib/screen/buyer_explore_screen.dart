import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/commodity_master_list.dart';
import '../services/product_service.dart';
import '../services/product_visibility_service.dart';
import '../services/image_helper.dart';
import '../services/market_price_helpers.dart';
import '../widgets/retry_message.dart';
import 'buyer_search_screen.dart';
import 'product_detail_screen.dart';

class BuyerExploreScreen extends StatefulWidget {
  const BuyerExploreScreen({super.key});

  @override
  State<BuyerExploreScreen> createState() => _BuyerExploreScreenState();
}

class _BuyerExploreScreenState extends State<BuyerExploreScreen> {
  static const Color _dark = Color(0xFF1B5E20);

  String _selectedCategory = 'All Postings';
  // Derived from the Commodity Master List so every category a farmer can
  // now pick on Add Product (Grains, Root Crops, Vegetables, Spices,
  // Fruits, Livestock, Fisheries) also has a matching buyer-side filter —
  // not a separately hand-maintained list that can fall out of sync.
  final List<String> _categories = ['All Postings', ...kCommodityMasterList.keys];

  final ProductService _productService = ProductService();

  String _selectedBarangay = 'All Locations';
  Map<String, String> _barangayByFarmerUid = {};
  Map<String, bool> _verifiedByFarmerUid = {};
  StreamSubscription? _usersSub;

  // Visibility-ranking inputs (ProductVisibilityService) — completed-order
  // count per product is the "demand" signal; seller verification feeds
  // "credibility" alongside each product's own rating/reviewCount.
  Map<String, int> _completedOrderCountByProduct = {};
  StreamSubscription? _completedOrdersSub;

  @override
  void initState() {
    super.initState();
    _usersSub = FirebaseFirestore.instance.collection('publicProfiles').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _barangayByFarmerUid = {
          for (final doc in snap.docs)
            if ((doc.data()['role'] ?? '') == 'farmer' &&
                (doc.data()['barangay'] ?? '').toString().isNotEmpty)
              doc.id: doc.data()['barangay'].toString(),
        };
        // Derived directly from approvalStatus — the single source of
        // truth for verification state across the whole app — rather than
        // the separate isVerified field, which existed only as a mirror
        // and could historically drift from it (see
        // verification_queue_view.dart's _setFarmerApproval).
        _verifiedByFarmerUid = {
          for (final doc in snap.docs)
            if ((doc.data()['role'] ?? '') == 'farmer') doc.id: doc.data()['approvalStatus'] == 'approved',
        };
      });
    });

    _completedOrdersSub = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final productId = (doc.data()['productId'] ?? '').toString();
        if (productId.isEmpty) continue;
        counts[productId] = (counts[productId] ?? 0) + 1;
      }
      setState(() => _completedOrderCountByProduct = counts);
    });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _completedOrdersSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshProducts() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        _buildCategoryChips(),
        _buildLocationChips(),
        const SizedBox(height: 4),
        Expanded(child: _buildProductGrid()),
      ],
    );
  }

  // Tapping this (not typing in it — it's not a real text field) opens the
  // dedicated Search Screen, which owns the entire search experience
  // (suggested/trending/recent searches, category browsing, recommended
  // products, and result matching) — Explore itself no longer performs
  // text search inline.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BuyerSearchScreen()),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey[500], size: 20),
                const SizedBox(width: 10),
                Text(
                  'Search crops, livestock, or farmers...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          return ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (_) => setState(() => _selectedCategory = category),
            selectedColor: _dark,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : _dark,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: selected ? _dark : _dark.withValues(alpha: 0.3)),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          );
        },
      ),
    );
  }

  Widget _buildLocationChips() {
    final barangays = _barangayByFarmerUid.values.toSet().toList()..sort();
    if (barangays.isEmpty) return const SizedBox.shrink();

    final options = ['All Locations', ...barangays];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final barangay = options[index];
          final selected = barangay == _selectedBarangay;
          return ChoiceChip(
            avatar: Icon(Icons.place_outlined,
                size: 14, color: selected ? Colors.white : Colors.grey[600]),
            label: Text(barangay),
            selected: selected,
            onSelected: (_) => setState(() => _selectedBarangay = barangay),
            selectedColor: Colors.grey[800],
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: selected ? Colors.grey[800]! : Colors.grey[300]!),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productService.allProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _dark));
        }
        if (snapshot.hasError) {
          return RetryMessage(
            message: 'Could not load products. Check your connection and try again.',
            onRetry: () => setState(() {}),
          );
        }
        var docs = snapshot.data?.docs ?? [];

        docs = docs
            .where((doc) =>
                doc.data()['isArchived'] != true &&
                doc.data()['isSuspended'] != true)
            .toList();

        if (_selectedCategory != 'All Postings') {
          docs = docs.where((doc) {
            final category = (doc.data()['category'] ?? '').toString();
            return category.toLowerCase() == _selectedCategory.toLowerCase();
          }).toList();
        }

        if (_selectedBarangay != 'All Locations') {
          docs = docs.where((doc) {
            final farmerId = (doc.data()['farmerId'] ?? '').toString();
            return _barangayByFarmerUid[farmerId] == _selectedBarangay;
          }).toList();
        }

        // Rank by demand + seller credibility + interaction (prescriptive
        // analytics: which listings get priority visibility). Ties — most
        // commonly an all-zero score on a fresh marketplace with no orders/
        // reviews/views yet — fall back to newest-first, today's old order.
        final scores = ProductVisibilityService.scoreProducts(
          products: {for (final d in docs) d.id: d.data()},
          completedOrderCountByProductId: _completedOrderCountByProduct,
          verifiedByFarmerId: _verifiedByFarmerUid,
        );
        docs.sort((a, b) {
          final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
          if (scoreCompare != 0) return scoreCompare;
          final aCreated = a.data()['createdAt'] as Timestamp?;
          final bCreated = b.data()['createdAt'] as Timestamp?;
          return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(aCreated?.millisecondsSinceEpoch ?? 0);
        });

        if (docs.isEmpty) {
          final isFiltered = _selectedBarangay != 'All Locations' ||
              _selectedCategory != 'All Postings';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFiltered ? Icons.search_off_rounded : Icons.eco_outlined,
                    size: 56,
                    color: Colors.grey[350],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedBarangay != 'All Locations'
                        ? 'No listings yet in $_selectedBarangay'
                        : 'No products available yet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isFiltered
                        ? 'Try a different search or clear your filters to see everything on offer.'
                        : 'New listings from local farmers show up here — check back soon!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 13.5),
                  ),
                  if (isFiltered) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedBarangay = 'All Locations';
                          _selectedCategory = 'All Postings';
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Clear filters'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _dark,
                        side: const BorderSide(color: _dark),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: _dark,
          onRefresh: _refreshProducts,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
            itemBuilder: (context, index) => _buildProductCard(docs[index]),
          ),
        );
      },
    );
  }

  Widget _buildProductCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = data['name'] ?? 'Unnamed Product';
    final category = data['category'] ?? 'General';
    final farmer = data['farmerName'] ?? 'Local Farmer';
    final price = (data['retailPrice'] as num?) ?? (data['price'] as num?) ?? 0;
    final wholesalePrice = (data['wholesalePrice'] as num?)?.toDouble();
    final wholesaleEnabled = data['wholesaleEnabled'] == true ||
        (data['wholesaleEnabled'] == null && wholesalePrice != null && wholesalePrice > 0);
    final quantity = (data['quantity'] as num?) ?? 0;
    final unit = (data['unit'] as String?) ?? unitForProductName(name.toString());
    final rating = (data['rating'] as num?)?.toDouble();
    final reviewCount = data['reviewCount'];

    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: doc.id, data: data)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 10,
              child: SizedBox(width: double.infinity, child: _buildProductImage(data)),
            ),
            Expanded(
              flex: 15,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.toString().toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.black87, height: 1.2)),
                    const SizedBox(height: 2),
                    if (rating != null)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
                          if (reviewCount != null) ...[
                            const SizedBox(width: 2),
                            Text('($reviewCount)', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ],
                      ),
                    const Spacer(),
                    Text(formatPriceWithUnit(price, unit),
                        style: const TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 16)),
                    if (wholesaleEnabled) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Wholesale available',
                          style: TextStyle(fontSize: 9.5, color: _dark, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 1),
                    Text("${formatStock(quantity, unit)} left", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    const SizedBox(height: 6),
                    Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 7,
                          backgroundColor: Color(0xFFDCEDC8),
                          child: Icon(Icons.person, size: 9, color: _dark),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(farmer, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(Map<String, dynamic> data) {
    final base64 = data['imageBase64']?.toString();
    final imageUrl = (data['imageUrl']?.toString().isNotEmpty == true)
        ? data['imageUrl']?.toString()
        : (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty)
            ? (data['imageUrls'] as List).first?.toString()
            : null;

    if (base64 != null && base64.isNotEmpty) {
      return Base64Image(
        base64Data: base64,
        fit: BoxFit.cover,
        fallback: Container(
          color: const Color(0xFFDCEDC8),
          child: const Icon(Icons.eco_rounded, size: 48, color: _dark),
        ),
      );
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(color: _dark)),
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFFDCEDC8),
          child: const Icon(Icons.broken_image, size: 48, color: _dark),
        ),
      );
    }
    return Container(
      color: const Color(0xFFDCEDC8),
      child: const Icon(Icons.eco_rounded, size: 48, color: _dark),
    );
  }
}
