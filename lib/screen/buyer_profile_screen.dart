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
import 'help_support_screen.dart';
import 'manage_account_screen.dart';
import 'notification_preferences_screen.dart';
import 'buyer_fulfillment_preferences_screen.dart';
import '../widgets/agri_refresh_indicator.dart';
import '../l10n/tr.dart';

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

  /// Opens Orders on its Completed tab (the Completed Orders count).
  final VoidCallback? onOpenCompletedOrders;

  const BuyerProfileScreen({
    super.key,
    required this.onLogout,
    this.onOpenCompletedOrders,
  });

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
    final t = tr(context);
    final user = FirebaseAuth.instance.currentUser;

    // The header stays put; pull-to-refresh starts under it.
    return Column(
      children: [
        // The band stays put; the title scrolls with the page below.
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
                  PageTitle(title: tr(context).navProfile),
                  const SizedBox(height: 4),

                  // ---- Photo, name, general location ----
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _profile,
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data();
                      final name =
                          [data?['name'], data?['fullName'], user?.displayName]
                              .map((v) => (v ?? '').toString().trim())
                              .firstWhere(
                                (v) => v.isNotEmpty,
                                orElse: () => 'Buyer',
                              );
                      final photoUrl =
                          data?['photoUrl']?.toString() ?? user?.photoURL;
                      // General area only — barangay and city, never a street
                      // address or a pin.
                      final location =
                          [data?['barangay'], data?['municipality']]
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

                  // ---- Everything on the page, as plain rows in labelled
                  // groups (no cards, no gear menu); notifications themselves
                  // are behind the bell on Explore. ----
                  ProfileSectionLabel(t.sectionActivity),
                  ProfileLinkTile(
                    icon: Icons.rate_review_outlined,
                    label: t.myReviews,
                    onTap: () => _open(const BuyerMyReviewsScreen()),
                  ),
                  ProfileLinkTile(
                    icon: Icons.favorite_border_rounded,
                    label: t.likedProducts,
                    onTap: () => _open(const BuyerSavedProductsScreen()),
                  ),
                  ProfileSectionLabel(t.sectionSettings),
                  ProfileLinkTile(
                    icon: Icons.local_shipping_outlined,
                    label: t.deliveryPickupPreferences,
                    onTap: () =>
                        _open(const BuyerFulfillmentPreferencesScreen()),
                  ),
                  ProfileLinkTile(
                    icon: Icons.notifications_none_rounded,
                    label: t.notificationSettings,
                    onTap: () => _open(const NotificationPreferencesScreen()),
                  ),
                  ProfileLinkTile(
                    icon: Icons.manage_accounts_outlined,
                    label: t.manageAccount,
                    onTap: () => _open(const ManageAccountScreen()),
                  ),
                  ProfileSectionLabel(t.sectionSupport),
                  ProfileLinkTile(
                    icon: Icons.help_outline,
                    label: t.helpSupport,
                    onTap: () => _open(const HelpSupportScreen(farmer: false)),
                  ),
                  const SizedBox(height: 8),
                  ProfileLinkTile(
                    icon: Icons.logout,
                    label: t.logOut,
                    destructive: true,
                    onTap: widget.onLogout,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
          // Each count opens what it counts.
          final stats = <(int, String, VoidCallback?)>[
            if (orders > 0)
              (
                orders,
                orders == 1 ? 'Completed Order' : 'Completed Orders',
                widget.onOpenCompletedOrders,
              ),
            if (reviews > 0)
              (
                reviews,
                reviews == 1 ? 'Review Given' : 'Reviews Given',
                () => _open(const BuyerMyReviewsScreen()),
              ),
          ];
          if (stats.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
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
                        child: InkWell(
                          onTap: stats[i].$3,
                          borderRadius: BorderRadius.circular(10),
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
