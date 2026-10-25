import 'dart:math';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/commodity_master_list.dart';
import '../services/product_service.dart';
import '../services/product_recommendation_service.dart';
import '../services/product_visibility_service.dart';
import '../services/saved_products_service.dart';
import '../widgets/page_header.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../widgets/app_search_bar.dart';
import 'buyer_search_screen.dart';
import 'product_detail_screen.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/save_product_button.dart';
import '../widgets/agri_empty_state.dart';
import '../l10n/tr.dart';

class BuyerExploreScreen extends StatefulWidget {
  /// The notification bell in this tab's header; [bellKey] lets the
  /// first-time walkthrough point at it.
  final VoidCallback? onNotificationsPressed;
  final Key? bellKey;

  const BuyerExploreScreen({
    super.key,
    this.onNotificationsPressed,
    this.bellKey,
  });

  @override
  State<BuyerExploreScreen> createState() => BuyerExploreScreenState();
}

class BuyerExploreScreenState extends State<BuyerExploreScreen> {
  static const Color _dark = AppTheme.dark;

  String _selectedCategory = 'All Postings';
  // Derived from the Commodity Master List so every category a farmer can
  // now pick on Add Product (Grains, Root Crops, Vegetables, Spices,
  // Fruits, Livestock) also has a matching buyer-side filter —
  // not a separately hand-maintained list that can fall out of sync.
  List<String> get _categories => [
    'All Postings',
    ...CommodityRegistry.instance.categories,
  ];

  final ProductService _productService = ProductService();

  // The listings, opened once — not again on every rebuild (a like, a
  // filter change…) — and again only on Retry.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _products = _productService
      .allProductsStream();

  final _grid = ScrollController();

  // Which mix of the feed is shown: 0 is the plain ranking; each Back to
  // the top (see [backToTop]) deals a fresh mix, so other products come
  // first. It only changes then, so the grid never reshuffles by itself.
  int _feedMix = 0;

  /// Back pressed on Explore: when the grid is scrolled down, it glides
  /// back to the top with a fresh mix of products and true is returned
  /// (Back is handled); at the top it returns false.
  bool backToTop() {
    if (!_grid.hasClients || _grid.offset <= 0) return false;
    setState(() {
      _feedMix++;
      _filtersHidden = false;
    });
    _grid.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  String _selectedBarangay = 'All Locations';

  // New posts wait for a refresh: the feed shows the listings that were
  // there when Explore opened ([_shownIds]); one posted while the buyer is
  // browsing appears only after pulling to refresh (or the next time the
  // app is opened), so the grid never jumps under their finger. Changes to
  // listings already shown (stock, price, removal) still apply at once.
  Set<String>? _shownIds;

  // Every listing in the latest data, for the next refresh.
  Set<String> _latestIds = {};

  // The posts the last refresh brought in — shown first, newest first.
  Set<String> _freshIds = {};

  // Scrolling down tucks the category and location filters away; scrolling
  // up (or reaching the top) brings them back.
  bool _filtersHidden = false;

  Map<String, String> _barangayByFarmerUid = {};
  Map<String, bool> _verifiedByFarmerUid = {};
  StreamSubscription? _usersSub;

  // Visibility-ranking inputs (ProductVisibilityService) — the "demand"
  // signal is each listing's own completedOrderCount (kept by Cloud
  // Functions; a buyer cannot read other buyers' orders to count them);
  // seller verification feeds
  // "credibility" alongside each product's own rating/reviewCount.

  // Liked Products hearts: the shared LikedProducts state, so a like made
  // here, in Search, on a farmer profile or in Product Details shows the
  // same everywhere.
  void _onLikesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    LikedProducts.instance
      ..start()
      ..addListener(_onLikesChanged);
    _usersSub = FirebaseFirestore.instance
        .collection('publicProfiles')
        .snapshots()
        .listen((snap) {
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
                if ((doc.data()['role'] ?? '') == 'farmer')
                  doc.id: doc.data()['approvalStatus'] == 'approved',
            };
          });
        });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _grid.dispose();
    LikedProducts.instance.removeListener(_onLikesChanged);
    super.dispose();
  }

  // Pull to refresh: brings in the posts made since the feed was loaded,
  // at the top.
  Future<void> _refreshProducts() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      final shown = _shownIds ?? const <String>{};
      _freshIds = _latestIds.difference(shown);
      _shownIds = {..._latestIds};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same title row as Messages, Orders and Profile.
        PageHeader(
          title: tr(context).navExplore,
          trailing: widget.onNotificationsPressed == null
              ? null
              : NotificationBell(
                  key: widget.bellKey,
                  onPressed: widget.onNotificationsPressed!,
                  color: PageHeader.onBandColor,
                ),
        ),
        _buildSearchBar(),
        // Tucked away while scrolling down the products (see
        // _filtersHidden).
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _filtersHidden
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_buildCategoryChips(), _buildLocationFilter()],
                  ),
          ),
        ),
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
      child: AppSearchBar(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BuyerSearchScreen()),
        ),
      ),
    );
  }

  // ---- Row 1: categories ----
  // Small individual pills, each only as wide as its own label, the same
  // size as the location pill below so the two rows read as a pair.
  // Plain pills in a horizontal list (not ChoiceChips, whose built-in
  // minimum height was taller than this row and got clipped). The list
  // scrolls edge to edge, so the last pill can always be brought fully
  // into view.
  Widget _buildCategoryChips() {
    final categories = _categories;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          return Center(
            child: _FilterPill(
              // Shown as just "All" — the stored value stays 'All Postings',
              // which the filtering compares against.
              label: category == 'All Postings' ? 'All' : category,
              selected: category == _selectedCategory,
              onTap: () => setState(() => _selectedCategory = category),
            ),
          );
        },
      ),
    );
  }

  // ---- Row 2: location ----
  // One compact pill showing the current choice; tapping it drops a small
  // menu straight below it (never a bottom sheet or a full-screen picker).
  final GlobalKey _locationPillKey = GlobalKey();

  Widget _buildLocationFilter() {
    final barangays = _barangayByFarmerUid.values.toSet().toList()..sort();
    if (barangays.isEmpty) return const SizedBox.shrink();

    final active = _selectedBarangay != 'All Locations';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _FilterPill(
          key: _locationPillKey,
          label: _selectedBarangay,
          selected: active,
          trailing: Icons.keyboard_arrow_down_rounded,
          onTap: () => _pickLocation(['All Locations', ...barangays]),
        ),
      ),
    );
  }

  // Scrolling the products: down hides the filters, up or back at the top
  // shows them.
  bool _onGridScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    bool? hide;
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse &&
          notification.metrics.pixels > 40) {
        hide = true;
      } else if (notification.direction == ScrollDirection.forward) {
        hide = false;
      }
    }
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels <= 0) {
      hide = false;
    }
    if (hide != null && hide != _filtersHidden) {
      setState(() => _filtersHidden = hide!);
    }
    return false;
  }

  // A floating dropdown anchored under the location pill: text-only rows,
  // the current choice on a light green background with a checkmark.
  // Tapping a row applies it and closes the menu; tapping outside just
  // closes it. With many locations only the list scrolls — the menu itself
  // stays this size.
  Future<void> _pickLocation(List<String> options) async {
    final pill = _locationPillKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (pill is! RenderBox || overlay is! RenderBox) return;

    const gap = 6.0;
    const rowHeight = 42.0;
    final pillTopLeft = pill.localToGlobal(Offset.zero, ancestor: overlay);
    final top = pillTopLeft.dy + pill.size.height + gap;
    // Never wider than the screen allows, never taller than the room left
    // below the pill (or about six rows).
    final maxWidth = (overlay.size.width - 32).clamp(160.0, 260.0);
    final maxHeight = (overlay.size.height - top - 24).clamp(
      rowHeight * 2,
      rowHeight * 6 + 12,
    );

    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pillTopLeft.dx,
        top,
        overlay.size.width - pillTopLeft.dx - maxWidth,
        0,
      ),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      constraints: BoxConstraints(
        minWidth: 200.0.clamp(0.0, maxWidth),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      items: [
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            height: rowHeight,
            padding: EdgeInsets.zero,
            child: _LocationOption(
              label: option,
              selected: option == _selectedBarangay,
              height: rowHeight,
            ),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _selectedBarangay = picked);
    }
  }

  Widget _buildProductGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _products,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _dark));
        }
        if (snapshot.hasError) {
          return RetryMessage(
            message:
                'Could not load products. Check your connection and try again.',
            onRetry: () => setState(() {
              _products = _productService.allProductsStream();
              _shownIds = null;
            }),
          );
        }
        var docs = snapshot.data?.docs ?? [];

        // What opening Explore found is what is shown; later posts wait for
        // a refresh (see _shownIds).
        _latestIds = {for (final d in docs) d.id};
        final shown = _shownIds ??= {..._latestIds};
        docs = docs
            .where(
              (doc) =>
                  shown.contains(doc.id) &&
                  doc.data()['isArchived'] != true &&
                  doc.data()['isSuspended'] != true,
            )
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
          completedOrderCountByProductId: {
            for (final d in docs)
              d.id: ProductRecommendationService.completedOrders(d.data()),
          },
          verifiedByFarmerId: _verifiedByFarmerUid,
        );
        // After a Back to the top, a fresh mix: each listing's rank is
        // nudged by a random amount fixed for that mix, so the order
        // changes but well-ranked listings still tend to come first.
        int created(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        if (_feedMix > 0) {
          final nudged = {
            for (final d in docs)
              d.id:
                  ((scores[d.id] ?? 0) + 1) *
                  (0.4 + Random(Object.hash(_feedMix, d.id)).nextDouble()),
          };
          docs.sort((a, b) => nudged[b.id]!.compareTo(nudged[a.id]!));
        } else {
          docs.sort((a, b) {
            final scoreCompare = (scores[b.id] ?? 0).compareTo(
              scores[a.id] ?? 0,
            );
            if (scoreCompare != 0) return scoreCompare;
            final aCreated = a.data()['createdAt'] as Timestamp?;
            final bCreated = b.data()['createdAt'] as Timestamp?;
            return (bCreated?.millisecondsSinceEpoch ?? 0).compareTo(
              aCreated?.millisecondsSinceEpoch ?? 0,
            );
          });
        }
        // The posts the last refresh brought in come first, newest first.
        if (_freshIds.isNotEmpty) {
          final fresh = docs.where((d) => _freshIds.contains(d.id)).toList()
            ..sort((a, b) => created(b).compareTo(created(a)));
          docs = [...fresh, ...docs.where((d) => !_freshIds.contains(d.id))];
        }

        if (docs.isEmpty) {
          final isFiltered =
              _selectedBarangay != 'All Locations' ||
              _selectedCategory != 'All Postings';

          return Center(
            child: AgriEmptyState(
              icon: isFiltered ? Icons.search_off_rounded : Icons.eco_outlined,
              title: _selectedBarangay != 'All Locations'
                  ? 'No listings yet in $_selectedBarangay'
                  : 'No products available yet',
              subtitle: isFiltered
                  ? 'Try a different search or clear your filters to see '
                        'everything on offer.'
                  : 'New marketplace listings will appear here once farmers '
                        'post products.',
              padding: const EdgeInsets.all(32),
              action: !isFiltered
                  ? null
                  : OutlinedButton.icon(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
            ),
          );
        }

        return AgriRefreshIndicator(
          color: _dark,
          onRefresh: _refreshProducts,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const padding = 12.0;
              const spacing = 12.0;
              // Card height follows the column width and the system text
              // size (see ExploreProductCard.extentFor) rather than a fixed
              // aspect ratio, which is what used to overflow on narrow
              // phones.
              final cardWidth =
                  (constraints.maxWidth - padding * 2 - spacing) / 2;
              return NotificationListener<ScrollNotification>(
                onNotification: _onGridScroll,
                child: GridView.builder(
                  controller: _grid,
                  padding: const EdgeInsets.fromLTRB(padding, 4, padding, 12),
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
                          builder: (_) => ProductDetailScreen(
                            productId: doc.id,
                            data: data,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// The pill used by both filter rows: dark green with white text when
// selected, white with a subtle border otherwise.
class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? trailing;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  static const Color _dark = AppTheme.dark;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : _dark;
    return Material(
      color: selected ? _dark : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _dark : _dark.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A very long name is cut with an ellipsis rather than
              // making one pill as wide as the screen.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 16, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// One row of the location dropdown — text only, no icons. The current
// choice sits on a light green background with a checkmark on the right.
class _LocationOption extends StatelessWidget {
  final String label;
  final bool selected;
  final double height;

  const _LocationOption({
    required this.label,
    required this.selected,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      color: selected ? AppTheme.tint : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.dark : Colors.black87,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, size: 18, color: AppTheme.dark),
          ],
        ],
      ),
    );
  }
}
