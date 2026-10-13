import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/page_header.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_menu.dart';
import 'farmer_edit_profile_screen.dart';
import 'buyer_my_reviews_screen.dart';
import 'buyer_saved_products_screen.dart';
import 'buyer_settings_screen.dart';
import 'buyer_fulfillment_preferences_screen.dart';
import 'notifications_screen.dart';
import '../widgets/agri_refresh_indicator.dart';

/// The buyer's Profile tab. Same look as the farmer's (header, the
/// avatar with its edit badge, name, then role-specific content), with
/// buyer content: a small activity summary and the buyer's own features,
/// then Log Out on its own at the bottom. There is no menu icon — every
/// option is on the page or inside Account Settings.
///
/// Shows only what is fine for the profile itself — photo, name and the
/// general saved location. The email address and other account details
/// live in Account Settings; the exact delivery details in
/// Delivery & Pickup.
class BuyerProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const BuyerProfileScreen({super.key, required this.onLogout});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  static const Color _dark = AppTheme.dark;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // Created once, not in build(), so a rebuild doesn't resubscribe.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _profile =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid ?? 'unknown')
          .snapshots();
  late final Stream<int> _completedOrders = FirebaseFirestore.instance
      .collection('orders')
      .where('buyerId', isEqualTo: _uid ?? '')
      .where('status', isEqualTo: 'completed')
      .snapshots()
      .map((snap) => snap.size);
  late final Stream<int> _reviewsGiven = FirebaseFirestore.instance
      .collection('productReviews')
      .where('buyerId', isEqualTo: _uid ?? '')
      .snapshots()
      .map(
        (snap) => snap.docs
            .where((d) => d.data()['moderationStatus'] != 'removed')
            .length,
      );

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  // Same avatar-with-edit-badge treatment as the farmer profile, opening
  // the same shared EditProfileScreen — account-detail editing (name,
  // phone, photo) isn't role-specific, so there's no reason to duplicate
  // that form for buyers.
  Widget _avatarWithEditBadge(String name, String? photoUrl) {
    return GestureDetector(
      onTap: () => _open(const EditProfileScreen()),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProfileAvatar(photoUrl: photoUrl, name: name, radius: 46),
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
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AgriRefreshIndicator(
      color: _dark,
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 90),
        child: Column(
          children: [
            const PageHeader(title: 'Profile'),
            const SizedBox(height: 4),

            // ---- Photo, name, general location ----
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _profile,
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final name =
                    [data?['name'], data?['fullName'], user?.displayName]
                        .map((v) => (v ?? '').toString().trim())
                        .firstWhere((v) => v.isNotEmpty, orElse: () => 'Buyer');
                final photoUrl =
                    data?['photoUrl']?.toString() ?? user?.photoURL;
                // General area only — barangay and city, never a street
                // address or a pin.
                final location = [data?['barangay'], data?['municipality']]
                    .map((v) => (v ?? '').toString().trim())
                    .where((v) => v.isNotEmpty)
                    .join(', ');

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _avatarWithEditBadge(name, photoUrl),
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
                            Icon(
                              Icons.place_outlined,
                              size: 15,
                              color: Colors.grey[600],
                            ),
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
                    ],
                  ),
                );
              },
            ),

            _activitySummary(),
            const SizedBox(height: 20),

            // ---- Buyer features, straight on the page (no popup menu).
            // Change Password, Privacy & Security and Help & Support are
            // inside Account Settings, so they are not repeated here. ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ProfileLinkTile(
                    icon: Icons.rate_review_outlined,
                    label: 'My Reviews',
                    onTap: () => _open(const BuyerMyReviewsScreen()),
                  ),
                  const SizedBox(height: 10),
                  ProfileLinkTile(
                    icon: Icons.favorite_border_rounded,
                    label: 'Liked Products',
                    onTap: () => _open(const BuyerSavedProductsScreen()),
                  ),
                  const SizedBox(height: 10),
                  ProfileLinkTile(
                    icon: Icons.local_shipping_outlined,
                    label: 'Delivery & Pickup Preferences',
                    onTap: () =>
                        _open(const BuyerFulfillmentPreferencesScreen()),
                  ),
                  const SizedBox(height: 10),
                  ProfileLinkTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    onTap: () => _open(const NotificationsScreen()),
                  ),
                  const SizedBox(height: 10),
                  ProfileLinkTile(
                    icon: Icons.settings_outlined,
                    label: 'Account Settings',
                    onTap: () => _open(const BuyerSettingsScreen()),
                  ),
                  const SizedBox(height: 18),
                  // Always the last thing on the page, and kept apart from
                  // the settings above. onLogout asks for confirmation
                  // before signing out (see BuyerMarketplaceScreen._logout).
                  ProfileFooter(onLogout: widget.onLogout),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "12 Completed Orders | 4 Reviews Given" — real counts only. A count of
  // zero is left out, and with nothing to show the whole row is.
  Widget _activitySummary() {
    return StreamBuilder<int>(
      stream: _completedOrders,
      builder: (context, ordersSnap) => StreamBuilder<int>(
        stream: _reviewsGiven,
        builder: (context, reviewsSnap) {
          final orders = ordersSnap.data ?? 0;
          final reviews = reviewsSnap.data ?? 0;
          final stats = [
            if (orders > 0)
              (orders, orders == 1 ? 'Completed Order' : 'Completed Orders'),
            if (reviews > 0)
              (reviews, reviews == 1 ? 'Review Given' : 'Reviews Given'),
          ];
          if (stats.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Colors.grey[300],
                        ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${stats[i].$1}',
                              style: AppTheme.heading(
                                18,
                              ).copyWith(color: _dark),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stats[i].$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
