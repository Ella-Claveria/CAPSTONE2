import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import 'role_selection_screen.dart';
import 'add_product_screen.dart';
import 'farmer_edit_profile_screen.dart';
import '../widgets/change_password_dialog.dart';

// Body-only widget — renders inside FarmerHomeScreen's Scaffold.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
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

    // Fire-and-forget: don't let a stuck FCM call block logout.
    unawaited(MessageService().unregisterFcmToken());

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

        final ImageProvider? imageProvider =
            (photoUrl != null && photoUrl.isNotEmpty)
            ? NetworkImage(photoUrl)
            : null;

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
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? const Icon(Icons.person, color: _dark, size: 52)
                    : null,
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
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      "You haven't posted any products yet.",
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

  Widget _productTile(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    final name = data['name']?.toString() ?? 'Unnamed product';
    final price = (data['price'] as num?)?.toDouble();
    final quantity = data['quantity'];
    final isArchived = data['isArchived'] == true;
    final isOutOfStock = !isArchived && ((quantity as num?)?.toInt() ?? 0) <= 0;

    final imageUrls =
        (data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final imageUrl = imageUrls.isNotEmpty
        ? imageUrls.first
        : data['imageUrl']?.toString();

    final subtitle = price != null
        ? '₱${price.toStringAsFixed(2)}/kg${quantity != null ? ' · Qty: $quantity' : ''}'
        : (quantity != null ? 'Qty: $quantity' : '');

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
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (isArchived || isOutOfStock) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
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
        final reviews =
            snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (reviews.isEmpty) {
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: reviews.take(3).map((review) {
              final data = review.data();
              final rating = (data['rating'] as num?)?.toInt() ?? 0;
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
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 14,
                          color: index < rating
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
            }).toList(),
          ),
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
      child: SingleChildScrollView(
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
                final muni = data?['municipality']?.toString() ?? 'Laurel';
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
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                );
              },
            ),
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
