import '../theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/commodity_master_list.dart';
import '../services/product_service.dart';
import '../services/product_recommendation_service.dart';
import '../services/product_visibility_service.dart';
import '../services/saved_products_service.dart';
import '../services/search_trends.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/save_product_button.dart';
import '../widgets/retry_message.dart';
import 'product_detail_screen.dart';
import 'farmer_storefront_screen.dart';
import '../widgets/agri_empty_state.dart';

/// The dedicated Buyer Search experience — opened by tapping the (non-
/// editable) search bar on Explore, never an inline field on the
/// marketplace itself. Owns the whole search flow on one screen: Suggested
/// Searches (while typing), Trending Searches, Recent Searches and
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
  static const Color _dark = AppTheme.dark;

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

  final ProductService _productService = ProductService();

  List<String> _trendingSearches = [];
  StreamSubscription? _trendingSub;

  // This buyer's own searches as (term, when), newest first; what is shown
  // is the latest 8 distinct terms since they last tapped "Clear".
  List<(String, int)> _recentRaw = [];
  int _recentClearedAt = 0;
  static const int _maxRecent = 8;

  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  List<String> _recentSearches = [];
  bool _recentSearchesLoaded = false;
  bool _recentSearchesError = false;
  StreamSubscription? _recentSub;

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
    //
    // Read from searchTrends — per-term, per-day totals kept by the
    // aggregateSearchTrend Cloud Function, with no buyer ids in them — not
    // from other buyers' raw searchEvents. Ranked over the last 7 days (see
    // topTrendingTerms); with too little activity the list is empty and
    // the section simply isn't shown.
    _trendingSub = FirebaseFirestore.instance
        .collection('searchTrends')
        .orderBy('updatedAt', descending: true)
        .limit(150)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(
            () => _trendingSearches = topTrendingTerms(
              snap.docs.map((d) => d.data()),
              now: DateTime.now(),
            ),
          );
        }, onError: (_) {});

    // RECENT SEARCHES = this logged-in buyer's own recent searches. No
    // orderBy paired with the equality filter (avoids needing a composite
    // Firestore index) — sorted and deduplicated client-side instead.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _loadRecentClearedAt(uid);

      // Liked products (shared state — also draws the hearts on the cards).
      LikedProducts.instance
        ..start()
        ..addListener(_onLikesChanged);

      _recentSub = FirebaseFirestore.instance
          .collection('searchEvents')
          .where('userId', isEqualTo: uid)
          .limit(50)
          .snapshots()
          .listen(
            (snap) {
              if (!mounted) return;
              final docs = [...snap.docs]
                ..sort((a, b) {
                  final at = a.data()['createdAt'] as Timestamp?;
                  final bt = b.data()['createdAt'] as Timestamp?;
                  return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                    at?.millisecondsSinceEpoch ?? 0,
                  );
                });
              _recentRaw = [
                for (final doc in docs)
                  (
                    _normalize((doc.data()['query'] ?? '').toString()),
                    // Not yet stamped by the server = just now.
                    (doc.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        DateTime.now().millisecondsSinceEpoch,
                  ),
              ];
              setState(() {
                _recentSearches = _visibleRecent();
                _recentSearchesLoaded = true;
                _recentSearchesError = false;
              });
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _recentSearchesLoaded = true;
                  _recentSearchesError = true;
                });
              }
            },
          );
    }

    // Visibility-ranking inputs for Recommended Products / results, same
    // signals Explore's own grid ranks by (ProductVisibilityService).
    _usersSub = FirebaseFirestore.instance
        .collection('publicProfiles')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            // Derived directly from approvalStatus — the single source of
            // truth for verification state — rather than the separate
            // isVerified field, which existed only as a mirror and could
            // historically drift from it.
            _verifiedByFarmerUid = {
              for (final doc in snap.docs)
                if ((doc.data()['role'] ?? '') == 'farmer')
                  doc.id: doc.data()['approvalStatus'] == 'approved',
            };
          });
        });
  }

  @override
  void dispose() {
    _trendingSub?.cancel();
    _recentSub?.cancel();
    LikedProducts.instance.removeListener(_onLikesChanged);
    _usersSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _visibleRecent() {
    final seen = <String>{};
    final recent = <String>[];
    for (final (term, at) in _recentRaw) {
      if (term.isEmpty || at <= _recentClearedAt || !seen.add(term)) continue;
      recent.add(term);
      if (recent.length >= _maxRecent) break;
    }
    return recent;
  }

  // "Clear" hides this buyer's history from their own list. The logged
  // searchEvents themselves are analytics (firestore.rules allows no
  // delete), so what is remembered — on this device — is the moment they
  // cleared it; only searches after that are shown again.
  static String _clearedKey(String uid) => 'recent_searches_cleared_$uid';

  Future<void> _loadRecentClearedAt(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recentClearedAt = prefs.getInt(_clearedKey(uid)) ?? 0;
    } catch (_) {}
    if (mounted) setState(() => _recentSearches = _visibleRecent());
  }

  Future<void> _clearRecentSearches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _recentClearedAt = DateTime.now().millisecondsSinceEpoch;
    setState(() => _recentSearches = _visibleRecent());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clearedKey(uid), _recentClearedAt);
    } catch (_) {}
  }

  // lowercase, trim, collapse repeated internal whitespace.
  static String _normalize(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: trimmed.length),
    );
    setState(() {
      _activeQuery = trimmed;
      _typed = trimmed;
    });
    _focusNode.unfocus();
    _logSearchEvent(trimmed);
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _typed = '';
      _activeQuery = null;
    });
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // SUGGESTED SEARCHES = supported commodity names relevant to the typed
  // text — a master-list-only autocomplete, distinct from Trending
  // Searches (real aggregated activity) below.
  List<String> get _suggestedSearches {
    if (_typed.trim().isEmpty) return const [];
    final q = _typed.trim().toLowerCase();
    return CommodityRegistry.instance.all
        .map((c) => c.name)
        .where((c) => c.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final showingResults = _activeQuery != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: showingResults ? _buildResults() : _buildBrowsingState(),
            ),
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
            icon: const AppBackIcon(),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            // The same bar as Marketplace's, here as a real field.
            child: AppSearchBar(
              controller: _controller,
              focusNode: _focusNode,
              onClear: _clearSearch,
              onChanged: (value) => setState(() {
                _typed = value;
                // Editing the field after a search was active returns to
                // live typing/suggestions instead of silently keeping a
                // stale results view on screen.
                _activeQuery = null;
              }),
              onSubmitted: _commitSearch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
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
                  Text(
                    term,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Search bar (above), then: Trending Searches, Recent Searches,
  // Recommended Products. Categories are not repeated here — Explore's
  // category pills already cover that. "Suggested Searches" only appears
  // while the buyer is typing (it is the field's autocomplete).
  Widget _buildBrowsingState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_suggestedSearches.isNotEmpty) ...[
          _sectionHeading('Suggested Searches'),
          const SizedBox(height: 10),
          _chipRow(_suggestedSearches, icon: Icons.search),
          const SizedBox(height: 22),
        ],
        // Hidden entirely until there is real, recent search activity.
        if (_trendingSearches.isNotEmpty) ...[
          _sectionHeading('Trending Searches'),
          const SizedBox(height: 10),
          _chipRow(_trendingSearches, icon: Icons.trending_up),
          const SizedBox(height: 22),
        ],
        if (_recentSearches.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _sectionHeading('Recent Searches')),
              TextButton(
                onPressed: _clearRecentSearches,
                style: TextButton.styleFrom(
                  foregroundColor: _dark,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _chipRow(_recentSearches, icon: Icons.history),
          const SizedBox(height: 22),
        ],
        if (_recentSearchesLoaded && _recentSearches.isEmpty) ...[
          _sectionHeading('Recent Searches'),
          const SizedBox(height: 6),
          Text(
            _recentSearchesError
                ? 'Could not load recent searches.'
                : 'No recent searches yet.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 22),
        ],
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
      // Kept on each listing by Cloud Functions (a buyer cannot read
      // other buyers' orders to count them here).
      completedOrderCountByProductId: {
        for (final d in docs)
          d.id: ProductRecommendationService.completedOrders(d.data()),
      },
      verifiedByFarmerId: _verifiedByFarmerUid,
    );
    final sorted = [...docs]
      ..sort((a, b) {
        final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
        if (scoreCompare != 0) return scoreCompare;
        final aCreated = a.data()['createdAt'] as Timestamp?;
        final bCreated = b.data()['createdAt'] as Timestamp?;
        return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(
          aCreated?.millisecondsSinceEpoch ?? 0,
        );
      });
    return sorted;
  }

  // Ranked by real marketplace performance — completed orders (50%),
  // rating (30%) and review count (20%) — among listings that are active
  // and in stock; see ProductRecommendationService. Where there is no
  // sales or review history yet, the most viewed and newest real listings
  // come first. Never random, never hardcoded.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _recommended(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final byId = {for (final doc in docs) doc.id: doc};
    return [
      for (final id in ProductRecommendationService.rank({
        for (final doc in docs) doc.id: doc.data(),
      }).take(8))
        byId[id]!,
    ];
  }

  // The same two-column cards as Explore, sized the same way (height from
  // the column width and text size — see ExploreProductCard.extentFor).
  Widget _productGrid(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: docs.length,
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
            final doc = docs[index];
            final data = doc.data();
            return ExploreProductCard(
              data: data,
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

  Widget _buildRecommendedProducts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productService.allProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load recommended products. Check your connection and try again.',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _dark)),
          );
        }
        final docs = snapshot.data!.docs
            .where(
              (d) =>
                  d.data()['isArchived'] != true &&
                  d.data()['isSuspended'] != true,
            )
            .toList();
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No products available yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          );
        }
        return _productGrid(_recommended(docs));
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
          return RetryMessage(
            message:
                'Could not load products. Check your connection and try again.',
            onRetry: () => setState(() {}),
          );
        }
        var docs = snapshot.data?.docs ?? [];
        docs = docs
            .where(
              (d) =>
                  d.data()['isArchived'] != true &&
                  d.data()['isSuspended'] != true,
            )
            .toList();

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
        final normalizedQuery = query?.trim().toLowerCase() ?? '';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('publicProfiles')
              .snapshots(),
          builder: (context, profileSnapshot) {
            final farmerHits = normalizedQuery.isEmpty
                ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                : (profileSnapshot.data?.docs ?? const []).where((profile) {
                    final data = profile.data();
                    if (data['role'] != 'farmer' ||
                        data['approvalStatus'] != 'approved') {
                      return false;
                    }
                    final name = (data['name'] ?? data['fullName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return name.contains(normalizedQuery);
                  }).toList();

            if (ranked.isEmpty &&
                farmerHits.isEmpty &&
                normalizedQuery.isNotEmpty) {
              return Center(
                child: AgriEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No results for "$query"',
                  subtitle: 'Try a different search term.',
                  padding: const EdgeInsets.all(32),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (farmerHits.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Farmers',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...farmerHits.map(_buildFarmerCard),
                  if (ranked.isNotEmpty) const SizedBox(height: 12),
                ],
                if (ranked.isNotEmpty) ...[
                  if (farmerHits.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Products',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  _productGrid(ranked),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFarmerCard(
    QueryDocumentSnapshot<Map<String, dynamic>> farmerDoc,
  ) {
    final farmer = farmerDoc.data();
    final name = (farmer['name'] ?? farmer['fullName'] ?? 'Farmer').toString();
    final photoUrl = farmer['photoUrl']?.toString() ?? '';
    final location =
        [farmer['barangay'], farmer['municipality'], farmer['province']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(', ');
    final rating = (farmer['rating'] as num?)?.toDouble();
    final reviewCount = (farmer['reviewCount'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFDCEDC8),
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? const Icon(Icons.person, color: _dark)
              : null,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (location.isNotEmpty) location else 'Verified farmer',
            if (rating != null && reviewCount > 0)
              '${rating.toStringAsFixed(1)} ★ · $reviewCount reviews',
          ].join('  ·  '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FarmerStorefrontScreen(farmerId: farmerDoc.id),
          ),
        ),
      ),
    );
  }
}
