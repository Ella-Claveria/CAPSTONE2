import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/commodity_master_list.dart';
import '../services/image_helper.dart';
import '../services/market_price_helpers.dart';
import '../services/product_service.dart';
import '../services/product_visibility_service.dart';
import 'product_detail_screen.dart';

/// The dedicated Buyer Search experience — opened by tapping the (non-
/// editable) search bar on Explore, never an inline field on the
/// marketplace itself. Owns the whole search flow on one screen: Suggested
/// Searches, Trending Searches, Recent Searches, Browse by Category, and
/// Recommended Products while browsing, switching to a live results grid
/// once the buyer actually searches. No bottom navigation bar, no Add to
/// Cart (this app has no cart — tapping a product always goes straight to
/// Product Detail, same as Explore).
class BuyerSearchScreen extends StatefulWidget {
  const BuyerSearchScreen({super.key});

  @override
  State<BuyerSearchScreen> createState() => _BuyerSearchScreenState();
}

class _BuyerSearchScreenState extends State<BuyerSearchScreen> {
  static const Color _dark = Color(0xFF1B5E20);

  // Same buyer + same normalized query within this window logs only once
  // instead of once per submission — see _logSearchEvent. "Do not count 15
  // repeated searches in 30 seconds as 15 independent demand signals."
  static const Duration _dedupWindow = Duration(seconds: 60);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Per-query last-logged time, for the client-side dedup above. Session-
  // scoped (resets if this screen is closed and reopened) rather than
  // enforced in Firestore itself — firestore.rules explicitly forbids any
  // update/delete on searchEvents ("allow update, delete: if false"), so a
  // server-side merge-and-increment dedup would be rejected outright
  // without a rules change. This still fully covers the actual scenario
  // described (a rapid burst of repeat taps/submissions in one sitting).
  final Map<String, DateTime> _lastLoggedAt = {};

  // Updates on every keystroke — drives the live "Suggested Searches" list
  // only. Never itself logged and never used to fetch results.
  String _typed = '';

  // Set only when the buyer actually commits to a search (submits the
  // field, or taps a suggested/trending/recent term/category) — this is
  // what switches to the results view AND is what gets logged. Staying
  // null means we're still in the browsing/suggestions state.
  String? _activeQuery;
  String? _activeCategory;

  final ProductService _productService = ProductService();

  List<String> _trendingSearches = [];
  StreamSubscription? _trendingSub;

  List<String> _recentSearches = [];
  StreamSubscription? _recentSub;

  Map<String, int> _completedOrderCountByProduct = {};
  StreamSubscription? _completedOrdersSub;
  Map<String, bool> _verifiedByFarmerUid = {};
  StreamSubscription? _usersSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });

    // TRENDING SEARCHES = real aggregated buyer search activity — every
    // buyer's logged searchEvents, most frequent query text first. A
    // single-field orderBy needs no composite index, unlike the per-buyer
    // query below.
    _trendingSub = FirebaseFirestore.instance
        .collection('searchEvents')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        // Normalize on read too, not just on write — legacy searchEvents
        // docs (logged before this normalization existed) may still have
        // mixed casing/spacing, and would otherwise fragment into separate
        // "trending" entries for what's really the same search.
        final query = _normalize((doc.data()['query'] ?? '').toString());
        if (query.isEmpty) continue;
        counts[query] = (counts[query] ?? 0) + 1;
      }
      final ranked = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      setState(() => _trendingSearches = ranked.take(8).map((e) => e.key).toList());
    });

    // RECENT SEARCHES = this logged-in buyer's own recent searches. No
    // orderBy paired with the equality filter (avoids needing a composite
    // Firestore index) — sorted and deduplicated client-side instead.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _recentSub = FirebaseFirestore.instance
          .collection('searchEvents')
          .where('userId', isEqualTo: uid)
          .limit(50)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        final docs = [...snap.docs]
          ..sort((a, b) {
            final at = a.data()['createdAt'] as Timestamp?;
            final bt = b.data()['createdAt'] as Timestamp?;
            return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
          });
        final seen = <String>{};
        final recent = <String>[];
        for (final doc in docs) {
          final query = _normalize((doc.data()['query'] ?? '').toString());
          if (query.isEmpty || seen.contains(query)) continue;
          seen.add(query);
          recent.add(query);
          if (recent.length >= 8) break;
        }
        setState(() => _recentSearches = recent);
      });
    }

    // Visibility-ranking inputs for Recommended Products / results, same
    // signals Explore's own grid ranks by (ProductVisibilityService).
    _usersSub = FirebaseFirestore.instance.collection('users').snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        // Derived directly from approvalStatus — the single source of
        // truth for verification state — rather than the separate
        // isVerified field, which existed only as a mirror and could
        // historically drift from it.
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
    _trendingSub?.cancel();
    _recentSub?.cancel();
    _usersSub?.cancel();
    _completedOrdersSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // lowercase, trim, collapse repeated internal whitespace.
  static String _normalize(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // Logs ONE meaningful search event — called only from _commitSearch
  // (submit, or picking a suggested/trending/recent term), never from
  // onChanged/every keystroke.
  Future<void> _logSearchEvent(String query) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final normalized = _normalize(query);
    if (normalized.isEmpty) return; // never log a blank search

    // Dedup: the same buyer resubmitting the same normalized query within
    // the window is one demand signal, not one per tap — "do not count 15
    // repeated searches in 30 seconds as 15 independent demand signals".
    // Keyed per query text so searching something else in between still
    // logs normally.
    final now = DateTime.now();
    final last = _lastLoggedAt[normalized];
    if (last != null && now.difference(last) < _dedupWindow) return;
    _lastLoggedAt[normalized] = now;

    try {
      await FirebaseFirestore.instance.collection('searchEvents').add({
        'userId': uid,
        'query': normalized,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort telemetry only — never surface this to the buyer.
    }
  }

  void _commitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _controller.text = trimmed;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: trimmed.length));
    setState(() {
      _activeQuery = trimmed;
      _activeCategory = null;
      _typed = trimmed;
    });
    _focusNode.unfocus();
    _logSearchEvent(trimmed);
  }

  void _browseCategory(String category) {
    setState(() {
      _activeCategory = category;
      _activeQuery = null;
    });
    _focusNode.unfocus();
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _typed = '';
      _activeQuery = null;
      _activeCategory = null;
    });
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // SUGGESTED SEARCHES = supported commodity names relevant to the typed
  // text — a master-list-only autocomplete, distinct from Trending
  // Searches (real aggregated activity) below.
  List<String> get _suggestedSearches {
    if (_typed.trim().isEmpty) return const [];
    final q = _typed.trim().toLowerCase();
    return kSupportedCommodities.where((c) => c.toLowerCase().contains(q)).take(8).toList();
  }

  static IconData _categoryIcon(String category) {
    switch (category) {
      case 'Grains':
        return Icons.grass;
      case 'Root Crops':
        return Icons.eco;
      case 'Vegetables':
        return Icons.local_florist;
      case 'Spices':
        return Icons.spa;
      case 'Fruits':
        return Icons.apple;
      case 'Livestock':
        return Icons.pets;
      case 'Fisheries':
        return Icons.set_meal;
      default:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showingResults = _activeQuery != null || _activeCategory != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: showingResults ? _buildResults() : _buildBrowsingState()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13.5, color: Colors.black87),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: Colors.grey[500], size: 18),
                          onPressed: _clearSearch,
                        ),
                  hintText: 'Search crops, livestock, or farmers...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13.5),
                ),
                onChanged: (value) => setState(() {
                  _typed = value;
                  // Editing the field after a search was active returns to
                  // live typing/suggestions instead of silently keeping a
                  // stale results view on screen.
                  _activeQuery = null;
                  _activeCategory = null;
                }),
                onSubmitted: _commitSearch,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String text) {
    return Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87));
  }

  Widget _chipRow(List<String> terms, {required IconData icon}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final term in terms)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _commitSearch(term),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(term, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBrowsingState() {
    final categories = kCommodityMasterList.keys.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_suggestedSearches.isNotEmpty) ...[
          _sectionHeading('Suggested Searches'),
          const SizedBox(height: 10),
          _chipRow(_suggestedSearches, icon: Icons.search),
          const SizedBox(height: 22),
        ],
        if (_trendingSearches.isNotEmpty) ...[
          _sectionHeading('Trending Searches'),
          const SizedBox(height: 10),
          _chipRow(_trendingSearches, icon: Icons.trending_up),
          const SizedBox(height: 22),
        ],
        if (_recentSearches.isNotEmpty) ...[
          _sectionHeading('Recent Searches'),
          const SizedBox(height: 10),
          _chipRow(_recentSearches, icon: Icons.history),
          const SizedBox(height: 22),
        ],
        // Never "Popular Categories" — AgriTrade+'s category list is
        // whatever the Commodity Master List currently defines, not a
        // fixed/curated "popular" set.
        _sectionHeading('Browse by Category'),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final category in categories)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _browseCategory(category),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_categoryIcon(category), color: _dark, size: 22),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          category,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionHeading('Recommended Products'),
        const SizedBox(height: 10),
        _buildRecommendedProducts(),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rankedByVisibility(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final scores = ProductVisibilityService.scoreProducts(
      products: {for (final d in docs) d.id: d.data()},
      completedOrderCountByProductId: _completedOrderCountByProduct,
      verifiedByFarmerId: _verifiedByFarmerUid,
    );
    final sorted = [...docs]
      ..sort((a, b) {
        final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
        if (scoreCompare != 0) return scoreCompare;
        final aCreated = a.data()['createdAt'] as Timestamp?;
        final bCreated = b.data()['createdAt'] as Timestamp?;
        return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(aCreated?.millisecondsSinceEpoch ?? 0);
      });
    return sorted;
  }

  Widget _buildRecommendedProducts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productService.allProductsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _dark)),
          );
        }
        final docs = snapshot.data!.docs
            .where((d) => d.data()['isArchived'] != true && d.data()['isSuspended'] != true)
            .toList();
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No products available yet.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          );
        }
        final top = _rankedByVisibility(docs).take(8).toList();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemBuilder: (context, index) => _buildProductCard(top[index]),
        );
      },
    );
  }

  Widget _buildResults() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productService.allProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _dark));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Something went wrong loading products.', style: TextStyle(color: Colors.black54)),
          );
        }
        var docs = snapshot.data?.docs ?? [];
        docs = docs
            .where((d) => d.data()['isArchived'] != true && d.data()['isSuspended'] != true)
            .toList();

        final category = _activeCategory;
        if (category != null) {
          docs = docs
              .where((d) => (d.data()['category'] ?? '').toString().toLowerCase() == category.toLowerCase())
              .toList();
        }

        final query = _activeQuery;
        if (query != null && query.isNotEmpty) {
          final q = query.toLowerCase();
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final farmer = (data['farmerName'] ?? '').toString().toLowerCase();
            return name.contains(q) || farmer.contains(q);
          }).toList();
        }

        final ranked = _rankedByVisibility(docs);

        if (ranked.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, size: 56, color: Colors.grey[350]),
                  const SizedBox(height: 16),
                  Text(
                    query != null ? 'No results for "$query"' : 'No listings in $category',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try a different search or browse another category.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: ranked.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemBuilder: (context, index) => _buildProductCard(ranked[index]),
        );
      },
    );
  }

  // Same card design as Explore's product grid (image, category, name,
  // rating, price+unit, wholesale badge, stock left, farmer) — deliberately
  // no Add to Cart, matching Explore and the rest of the app (there is no
  // shopping cart in AgriTrade+; a product always leads to Product Detail).
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: doc.id, data: data)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 10, child: SizedBox(width: double.infinity, child: _buildProductImage(data))),
            Expanded(
              flex: 15,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.toString().toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.black87, height: 1.2)),
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
                    // FittedBox: a long unit like "kg liveweight" wrapping
                    // to a second line would overflow this fixed-aspect-
                    // ratio card — scaling the string down to fit one line
                    // keeps every character of the real unit intact.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(formatPriceWithUnit(price, unit),
                          style: const TextStyle(color: _dark, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    if (wholesaleEnabled) ...[
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Wholesale available',
                            style: TextStyle(fontSize: 9.5, color: _dark, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(height: 1),
                    Text(
                      "${formatStock(quantity, unit)} left",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
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
                          child: Text(farmer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator(color: _dark)),
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
