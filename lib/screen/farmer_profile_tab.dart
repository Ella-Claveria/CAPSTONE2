import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/market_price_helpers.dart';
import '../data/commodity_master_list.dart';
import 'role_selection_screen.dart';
import 'add_product_screen.dart';
import 'farmer_edit_profile_screen.dart';
import 'farmer_reviews_screen.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/shimmer.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/retry_message.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  bool _isRefreshing = false;

  final ProductService _productService = ProductService();
  // 'active' | 'archived' — which of the farmer's own listings to show.
  String _productFilter = 'active';

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await AuthService().logOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text('$feature — coming soon.'),
      ),
    );
  }

  Widget _menuButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: _dark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            _showComingSoon(context, 'Account Settings');
            break;
          case 'password':
            showChangePasswordDialog(context);
            break;
          case 'help':
            _showComingSoon(context, 'Help & Support');
            break;
          case 'logout':
            _handleLogout(context);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined, color: _dark),
            title: Text(
              'Account Settings',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline, color: _dark),
            title: Text(
              'Change Password',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'help',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.help_outline, color: _dark),
            title: Text(
              'Help & Support',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              'Log Out',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      ],
    );
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
                          photoUrl!,
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
          const SizedBox(height: 10),
          Row(
            children: [
              _productFilterChip('Active', 'active'),
              const SizedBox(width: 8),
              _productFilterChip('Archived', 'archived'),
            ],
          ),
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
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      showArchived
                          ? "You don't have any archived products."
                          : "You haven't posted any active products yet.",
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < docs.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      _productTile(context, docs[i].id, docs[i].data()),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _productFilterChip(String label, String value) {
    final selected = _productFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _productFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _dark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _dark : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey[700],
          ),
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
                  name,
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
          subtitle: subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                )
              : null,
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[500]),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddProductScreen(productId: id, existingData: data),
                    ),
                  );
                  break;
                case 'quantity':
                  _showUpdateQuantityDialog(context, id, name, quantity, unit);
                  break;
                case 'archive':
                  _setArchived(context, id, !isArchived);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, color: _dark),
                  title: Text('Edit Product', style: TextStyle(fontSize: 14)),
                ),
              ),
              const PopupMenuItem(
                value: 'quantity',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined, color: _dark),
                  title: Text(
                    'Update Quantity',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    color: isArchived ? _dark : Colors.orange[800],
                  ),
                  title: Text(
                    isArchived ? 'Restore Listing' : 'Archive Listing',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddProductScreen(productId: id, existingData: data),
            ),
          ),
        ),
        _productReviews(id),
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cannot archive product'),
          content: const Text(
            'This product has orders that are not finished yet. Resolve or complete those orders before archiving this product.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
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
    final countBased = isCountBasedUnit(unit);
    final current = currentQuantity is num
        ? currentQuantity
        : num.tryParse(currentQuantity?.toString() ?? '') ?? 0;
    final controller = TextEditingController(
      text: countBased ? current.toStringAsFixed(0) : current.toString(),
    );
    final newQuantity = await showDialog<num?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update Available Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(
                decimal: !countBased,
              ),
              decoration: InputDecoration(
                labelText: 'Available Stock ($unit)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop<num?>(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = num.tryParse(controller.text.trim());
              if (parsed == null || parsed < 0) {
                _snack(
                  dialogContext,
                  'Please enter a valid, non-negative quantity.',
                );
                return;
              }
              if (countBased && parsed != parsed.roundToDouble()) {
                _snack(
                  dialogContext,
                  'Available Stock for $unit must be a whole number.',
                );
                return;
              }
              Navigator.of(dialogContext).pop<num?>(parsed);
            },
            child: const Text(
              'Save',
              style: TextStyle(color: _dark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || newQuantity == null) return;
    final error = await _productService.updateQuantity(id, newQuantity);
    if (!context.mounted) return;
    _snack(
      context,
      error ?? 'Available Stock updated to ${formatStock(newQuantity, unit)}.',
    );
  }

  Widget _productReviews(String productId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('productReviews')
          .where('productId', isEqualTo: productId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Could not load reviews.'),
            ),
          );
        }
        final reviews =
            snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final validReviews = reviews.where((review) {
          final data = review.data();
          final rating = data['rating'];
          return data['moderationStatus'] != 'removed' &&
              rating is num &&
              rating >= 0.5 &&
              rating <= 5;
        }).toList();
        if (validReviews.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No reviews yet.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),
          );
        }
        final ratingTotal = validReviews.fold<num>(
          0,
          (total, review) => total + (review.data()['rating'] as num),
        );
        final averageRating = ratingTotal / validReviews.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 3),
                  Text(
                    '${averageRating.toStringAsFixed(1)} · ${validReviews.length} ${validReviews.length == 1 ? 'review' : 'reviews'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              ...validReviews.take(3).map((review) {
                final data = review.data();
                final rating = (data['rating'] as num).toDouble();
                final comment = data['comment']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                          5,
                          (index) => Icon(
                            rating >= index + 1
                              ? Icons.star_rounded
                              : rating >= index + 0.5
                                ? Icons.star_half_rounded
                                : Icons.star_border_rounded,
                            size: 14,
                            color: rating >= index + 0.5
                                ? Colors.amber
                                : Colors.grey[400],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          comment.isEmpty ? 'Rated by buyer' : comment,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _farmerRatingSummary() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .where('farmerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        var ratingPoints = 0.0;
        var reviewCount = 0;
        for (final product in snapshot.data?.docs ?? const []) {
          final data = product.data();
          final productRating = (data['rating'] as num?)?.toDouble() ?? 0;
          final productReviewCount =
              (data['reviewCount'] as num?)?.toInt() ?? 0;
          if (productReviewCount <= 0 ||
              productRating < 1 ||
              productRating > 5) {
            continue;
          }
          ratingPoints += productRating * productReviewCount;
          reviewCount += productReviewCount;
        }
        final rating = reviewCount == 0 ? 0 : ratingPoints / reviewCount;
        return Column(
          children: [
            Text(
              reviewCount == 0
                  ? 'No reviews yet'
                  : '${rating.toStringAsFixed(1)} ★',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (reviewCount > 0)
              Text(
                '$reviewCount ${reviewCount == 1 ? 'Review' : 'Reviews'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FarmerReviewsScreen()),
              ),
              child: const Text('View All Reviews'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Farmer';

    return RefreshIndicator(
      color: _dark,
      onRefresh: _refreshData,
      child: _isRefreshing
          ? const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: ProfileTabSkeleton(),
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              child: Column(
                children: [
                  // ---- Hamburger menu (top right) — Account Settings / Help / Log Out ----
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _menuButton(context),
                    ),
                  ),

                  // ---- Avatar with edit badge ----
                  _avatarWithEditBadge(context),
                  const SizedBox(height: 10),

                  // ---- Name ----
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
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
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
