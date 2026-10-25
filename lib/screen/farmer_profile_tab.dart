import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/product_share_service.dart';
import '../services/market_price_helpers.dart';
import '../services/review_stats.dart';
import '../data/commodity_master_list.dart';
import 'role_selection_screen.dart';
import 'add_product_screen.dart';
import 'farmer_edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'farmer_reviews_screen.dart';
import '../widgets/page_header.dart';
import '../widgets/profile_settings_menu.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/update_stock_dialog.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/retry_message.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../l10n/tr.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const Color _dark = AppTheme.dark;
  static const Color _accent = Color(0xFFDCEDC8);
  final ProductService _productService = ProductService();
  // The farmer's own products, for the overall rating — created once.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myProductsForRating =
      _productService.myProductsStream();
  // 'active' | 'archived' — which of the farmer's own listings to show.
  String _productFilter = 'active';

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showAgriConfirm(
      context: context,
      icon: Icons.logout,
      tone: AgriTone.destructive,
      title: tr(context).logOut,
      message: tr(context).logOutConfirm,
      confirmLabel: tr(context).logOut,
    );
    if (!confirm) return;

    await AuthService().logOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  // ---- Settings (gear) menu beside the Profile title ----
  // Share My Store first, then settings and help, and Log Out last — in
  // red, after a divider.
  Widget _profileMenu(BuildContext context) => ProfileSettingsMenu(
    onShareStore: () => _shareStore(context),
    onHelp: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelpSupportScreen(farmer: true)),
    ),
    onLogout: () => _handleLogout(context),
  );

  Future<void> _shareStore(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await ProductShareService.shareStore(context, uid);
      if (!shared) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Add a product first. There is nothing to share yet.',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not share your store. Try again.')),
      );
    }
  }

  // ---- Avatar with an edit badge sitting on top of it ----
  // Tapping the avatar (or the badge) opens the full Edit Profile
  // screen, where the photo-change UI (camera icon + "Change Photo")
  // actually lives.
  Widget _avatarWithEditBadge(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid ?? '')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final photoUrl = data?['photoUrl']?.toString() ?? user?.photoURL;

        final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: _accent,
                child: hasPhoto
                    ? ClipOval(
                        child: Image.network(
                          photoUrl,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.person, color: _dark, size: 52),
                        ),
                      )
                    : const Icon(Icons.person, color: _dark, size: 52),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _dark,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- My Products ----
  // Lists the signed-in farmer's own listings. Matched by an 'ownerId'
  // field on each product doc — rename this to whatever field your
  // ProductService.addProduct() actually writes (e.g. 'farmerId', 'uid').
  Widget _myProductsSection(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MY PRODUCTS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddProductScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, size: 16, color: _dark),
                      SizedBox(width: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Active | Archived, with the current one underlined; swiping the
          // list below sideways moves between them too.
          // Two equal halves, like the Orders tabs.
          Row(
            children: [
              Expanded(
                child: _productFilterTab(tr(context).productsActive, 'active'),
              ),
              Expanded(
                child: _productFilterTab(
                  tr(context).productsArchived,
                  'archived',
                ),
              ),
            ],
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('farmerId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Shimmer(
                    child: Column(
                      children: [
                        ProductRowSkeleton(),
                        Divider(height: 1, indent: 16, endIndent: 16),
                        ProductRowSkeleton(),
                      ],
                    ),
                  );
                }
                if (snap.hasError) {
                  return RetryMessage(
                    message:
                        'Could not load your listings. Check your connection and retry.',
                    onRetry: () => setState(() {}),
                  );
                }

                final showArchived = _productFilter == 'archived';
                final docs = (snap.data?.docs ?? [])
                    .where(
                      (d) => (d.data()['isArchived'] == true) == showArchived,
                    )
                    .toList();
                final Widget list = docs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          showArchived
                              ? "You don't have any archived products."
                              : "You haven't posted any active products yet.",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < docs.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                            _productTile(context, docs[i].id, docs[i].data()),
                          ],
                        ],
                      );
                return _swipeBetweenFilters(list);
              },
            ),
          ),
        ],
      ),
    );
  }

  // One half of Active | Archived: its label centred, and — for the one
  // showing — dark green with a green bar under the whole half. Tapping
  // it works too.
  Widget _productFilterTab(String label, String value) {
    final selected = _productFilter == value;
    return InkWell(
      onTap: () => _showProductFilter(value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _dark : Colors.grey[500],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 2.5,
            width: double.infinity,
            decoration: BoxDecoration(
              color: selected ? _dark : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // Which way the list last moved: -1 to Archived (it slides in from the
  // right), 1 back to Active.
  int _filterDirection = -1;

  void _showProductFilter(String value) {
    if (value == _productFilter) return;
    setState(() {
      _filterDirection = value == 'archived' ? -1 : 1;
      _productFilter = value;
    });
  }

  // The list, swiped sideways to move between Active and Archived — left
  // for Archived, right for Active — sliding the new list in from that side.
  Widget _swipeBetweenFilters(Widget list) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -250) _showProductFilter('archived');
        if (velocity > 250) _showProductFilter('active');
      },
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey(_productFilter);
            final from = Offset(incoming ? -_filterDirection * 1.0 : 0, 0);
            final to = Offset(incoming ? 0 : _filterDirection * 1.0, 0);
            final slide = incoming
                ? Tween(begin: from, end: Offset.zero).animate(animation)
                : Tween(begin: to, end: Offset.zero).animate(animation);
            return SlideTransition(position: slide, child: child);
          },
          child: KeyedSubtree(key: ValueKey(_productFilter), child: list),
        ),
      ),
    );
  }

  Widget _productTile(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final name = data['name']?.toString() ?? 'Unnamed product';
    final price = (data['price'] as num?)?.toDouble();
    final quantity = data['quantity'];
    final unit = (data['unit'] as String?) ?? unitForProductName(name);
    final isArchived = data['isArchived'] == true;
    final saveCount = (data['saveCount'] as num?)?.toInt() ?? 0;
    final isOutOfStock =
        !isArchived && ((quantity as num?)?.toDouble() ?? 0) <= 0;

    final imageUrls =
        (data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final imageUrl = imageUrls.isNotEmpty
        ? imageUrls.first
        : data['imageUrl']?.toString();

    final stockText = quantity is num
        ? 'Available Stock: ${formatStock(quantity, unit)}'
        : '';
    final subtitle = price != null
        ? '${formatPriceWithUnit(price, unit)}${stockText.isEmpty ? '' : ' · $stockText'}'
        : stockText;

    return Column(
      children: [
        ListTile(
          // Less room on the right, so the ⋮ sits near the card's edge,
          // in line with "View Reviews" below it.
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          horizontalTitleGap: 12,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 46,
                      height: 46,
                      color: _accent,
                      child: const Icon(
                        Icons.eco_outlined,
                        color: _dark,
                        size: 22,
                      ),
                    ),
                  )
                : Container(
                    width: 46,
                    height: 46,
                    color: _accent,
                    child: const Icon(
                      Icons.eco_outlined,
                      color: _dark,
                      size: 22,
                    ),
                  ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  withSellingOption(name, data),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isArchived || isOutOfStock) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isArchived ? Colors.grey[300] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isArchived ? 'ARCHIVED' : 'OUT OF STOCK',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isArchived ? Colors.grey[700] : Colors.orange[800],
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: subtitle.isNotEmpty || saveCount > 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[600],
                        ),
                      ),
                    // How many buyers liked this listing — a number
                    // only (kept by the syncProductSaveCount Cloud
                    // Function); who they are is never available here.
                    if (saveCount > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: _dark,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            saveCount == 1 ? '1 like' : '$saveCount likes',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _dark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                )
              : null,
          // The same compact menu Messages uses (showAgriPopupMenu),
          // dropped from this product's own ⋮ button.
          trailing: Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Product actions',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_vert, color: Colors.grey[500]),
              onPressed: () => _openProductMenu(
                buttonContext,
                id: id,
                data: data,
                name: name,
                quantity: quantity,
                unit: unit,
                isArchived: isArchived,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddProductScreen(productId: id, existingData: data),
            ),
          ),
        ),
        _productRating(id, data),
      ],
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(message),
      ),
    );
  }

  // Active listing: Share, Edit, Update Quantity, Archive. An archived
  // one is hidden from buyers and read-only, so it only offers its
  // details and Restore — nothing to share, edit or restock until then.
  Future<void> _openProductMenu(
    BuildContext buttonContext, {
    required String id,
    required Map<String, dynamic> data,
    required String name,
    required dynamic quantity,
    required String unit,
    required bool isArchived,
  }) async {
    final action = await showAgriPopupMenu<String>(
      anchorContext: buttonContext,
      items: isArchived
          ? const [
              AgriMenuItem(
                value: 'view',
                icon: Icons.visibility_outlined,
                label: 'View Details',
              ),
              AgriMenuItem(
                value: 'archive',
                icon: Icons.unarchive_outlined,
                label: 'Restore Listing',
              ),
            ]
          : const [
              AgriMenuItem(
                value: 'share',
                icon: Icons.share_outlined,
                label: 'Share Product',
              ),
              AgriMenuItem(
                value: 'edit',
                icon: Icons.edit_outlined,
                label: 'Edit Product',
              ),
              AgriMenuItem(
                value: 'quantity',
                icon: Icons.inventory_2_outlined,
                label: 'Update Quantity',
              ),
              AgriMenuItem(
                value: 'archive',
                icon: Icons.archive_outlined,
                label: 'Archive Listing',
              ),
            ],
    );
    if (action == null || !buttonContext.mounted) return;
    switch (action) {
      case 'view':
      case 'edit':
        Navigator.push(
          buttonContext,
          MaterialPageRoute(
            builder: (_) => AddProductScreen(productId: id, existingData: data),
          ),
        );
      case 'quantity':
        _showUpdateQuantityDialog(buttonContext, id, name, quantity, unit);
      case 'archive':
        _setArchived(buttonContext, id, !isArchived);
      case 'share':
        ProductShareService.share(buttonContext, id, data);
    }
  }

  Future<void> _setArchived(
    BuildContext context,
    String id,
    bool archive,
  ) async {
    final error = archive
        ? await _productService.archiveProduct(id)
        : await _productService.unarchiveProduct(id);
    if (!context.mounted) return;
    if (archive && error == ProductService.archiveBlockedByOrdersMessage) {
      await showAgriDialog<void>(
        context: context,
        builder: (dialogContext) => AgriDialog(
          icon: Icons.archive_outlined,
          tone: AgriTone.warning,
          title: const Text('Cannot archive product'),
          content: const Text(
            'This product has orders that are not finished yet. Resolve or complete those orders before archiving this product.',
          ),
          actions: [
            AgriDialogButton(
              label: 'OK',
              kind: AgriButtonKind.primary,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      return;
    }
    _snack(
      context,
      error ??
          (archive
              ? 'Listing archived — hidden from the marketplace until you restore it.'
              : 'Listing restored — visible in the marketplace again.'),
    );
  }

  // Farmers can always manually correct Available Stock (independent of
  // order-driven deduction) — whole numbers only for count-based units
  // (piece/head), decimals allowed for weight-based ones (kg/kg liveweight).
  Future<void> _showUpdateQuantityDialog(
    BuildContext context,
    String id,
    String name,
    dynamic currentQuantity,
    String unit,
  ) async {
    final current = currentQuantity is num
        ? currentQuantity
        : num.tryParse(currentQuantity?.toString() ?? '') ?? 0;
    // The dialog owns its own text controller (see UpdateStockDialog) —
    // it must outlive this call returning, since the dialog is still
    // closing at that point. Null means cancelled: nothing is saved.
    final newQuantity = await showUpdateStockDialog(
      context,
      name: name,
      currentQuantity: current,
      unit: unit,
      onInvalid: _snack,
    );
    if (!context.mounted || newQuantity == null) return;
    final error = await _productService.updateQuantity(id, newQuantity);
    if (!context.mounted) return;
    _snack(
      context,
      error ?? 'Available Stock updated to ${formatStock(newQuantity, unit)}.',
    );
  }

  // A product's rating line: "4.7 ★ · 18 reviews · View Reviews". Reads
  // the totals stored on the product (kept current by the
  // recomputeProductReviewStats Cloud Function) rather than loading every
  // review for every product in the list.
  Widget _productRating(String productId, Map<String, dynamic> product) {
    final summary = productRating(product);
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 12, 8),
      child: Row(
        children: [
          if (summary.count == 0)
            Text(
              tr(context).noReviewsYet,
              style: TextStyle(fontSize: 12, color: Colors.black45),
            )
          else ...[
            Text(
              formatRating(summary.average),
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
            const SizedBox(width: 6),
            Text(
              reviewCountLabel(summary.count),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FarmerReviewsScreen(
                    productId: productId,
                    productName: product['name']?.toString(),
                  ),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _dark,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(tr(context).viewReviews),
            ),
          ],
        ],
      ),
    );
  }

  // The farmer's overall rating across all their products, weighted by
  // each product's number of reviews (see combineProductRatings).
  Widget _farmerRatingSummary() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myProductsForRating,
      builder: (context, snapshot) {
        final summary = combineProductRatings(
          (snapshot.data?.docs ?? const []).map((doc) => doc.data()),
        );
        // Nothing to show until the first valid review arrives — a new
        // farmer (no products, or products with no reviews) sees no empty
        // rating card. It appears on its own once a review exists.
        if (summary.count == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall Product Rating',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    ...[
                      Row(
                        children: [
                          Text(
                            formatRating(summary.average),
                            style: GoogleFonts.montserrat(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _dark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RatingStars(summary.average, size: 17),
                        ],
                      ),
                      Text(
                        'Based on ${reviewCountLabel(summary.count)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FarmerReviewsScreen(),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _dark,
                  textStyle: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(tr(context).viewAllReviews),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Farmer';

    // The header stays put; pull-to-refresh starts under it.
    return Column(
      children: [
        // The band stays put; the title (with the account menu opposite
        // it) scrolls with the page below.
        PageHeader(title: tr(context).navProfile, includeTitle: false),
        Expanded(
          child: AgriRefreshIndicator(
            color: _dark,
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              child: Column(
                children: [
                  PageTitle(
                    title: tr(context).navProfile,
                    trailing: _profileMenu(context),
                  ),

                  // ---- Avatar with edit badge ----
                  _avatarWithEditBadge(context),
                  const SizedBox(height: 10),

                  // ---- Name ----
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ---- Location ----
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user?.uid ?? 'unknown')
                        .snapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final barangay = data?['barangay']?.toString();
                      final muni =
                          data?['municipality']?.toString() ?? 'Laurel';
                      final prov = data?['province']?.toString() ?? 'Batangas';
                      final location = (barangay != null && barangay.isNotEmpty)
                          ? '$barangay, $muni, $prov'
                          : '$muni, $prov';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            location,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  _farmerRatingSummary(),
                  const SizedBox(height: 24),

                  // ---- My Products ----
                  _myProductsSection(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
