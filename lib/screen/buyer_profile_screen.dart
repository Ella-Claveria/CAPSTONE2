import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../widgets/buyer_location_picker.dart';
import '../widgets/change_password_dialog.dart';
import 'farmer_edit_profile_screen.dart';
import 'buyer_settings_screen.dart';
import 'buyer_support_screen.dart';

class BuyerProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const BuyerProfileScreen({super.key, required this.onLogout});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _accent = Color(0xFFDCEDC8);
  final _authService = AuthService();

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  // Opens the same popup used when placing an order, pre-filled with
  // whatever readable address is already on file, and saves whatever
  // comes back — the "Saved Location" row below refreshes on its own
  // since it's a live stream of the same users/{uid} doc this writes to.
  Future<void> _editLocation(Map<String, dynamic>? data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final region = data?['region']?.toString();
    final province = data?['province']?.toString();
    final city = data?['municipality']?.toString();
    final barangay = data?['barangay']?.toString();

    BuyerLocationResult? initial;
    if (province != null &&
        province.isNotEmpty &&
        city != null &&
        city.isNotEmpty &&
        barangay != null &&
        barangay.isNotEmpty) {
      initial = BuyerLocationResult(
        region: (region != null && region.isNotEmpty) ? region : province,
        province: province,
        city: city,
        barangay: barangay,
      );
    }

    final result = await showBuyerLocationPicker(context, initial: initial);
    if (result == null || !mounted) return;
    await _authService.saveBuyerLocation(
      uid: uid,
      latitude: result.latitude,
      longitude: result.longitude,
      region: result.region,
      province: result.province,
      city: result.city,
      barangay: result.barangay,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Location updated.')));
  }

  Widget _menuButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: _dark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BuyerSettingsScreen()),
            );
            break;
          case 'password':
            showChangePasswordDialog(context);
            break;
          case 'help':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BuyerSupportScreen()),
            );
            break;
          case 'logout':
            widget.onLogout();
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

  // Same avatar-with-edit-badge treatment as the farmer profile, opening
  // the same shared EditProfileScreen — account-detail editing (name,
  // phone, location, photo) isn't role-specific, so there's no reason to
  // duplicate that form for buyers.
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Buyer';

    return RefreshIndicator(
      color: _dark,
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 90),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Align(
                alignment: Alignment.topRight,
                child: _menuButton(context),
              ),
            ),

            _avatarWithEditBadge(context),
            const SizedBox(height: 10),

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

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid ?? 'unknown')
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() ?? const <String, dynamic>{};
                final trusted = data['trustedBuyer'] == true;
                final count =
                    (data['trustedBuyerReviewCount'] as num?)?.toInt() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: trusted
                        ? const Color(0xFFE8F5E9)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trusted
                            ? Icons.verified_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: trusted ? _dark : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        trusted
                            ? 'Trusted Buyer'
                            : 'Trusted Buyer: $count/3 reviews',
                        style: TextStyle(
                          color: trusted ? _dark : Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid ?? 'unknown')
                  .snapshots(),
              builder: (context, snapshot) {
                final profile =
                    snapshot.data?.data() ?? const <String, dynamic>{};
                final trusted = profile['trustedBuyer'] == true;
                final reviewCount =
                    (profile['trustedBuyerReviewCount'] as num?)?.toInt() ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: trusted
                        ? const Color(0xFFE8F5E9)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trusted
                            ? Icons.verified_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: trusted ? _dark : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        trusted
                            ? 'Trusted Buyer'
                            : 'Trusted Buyer: $reviewCount/3 reviews',
                        style: TextStyle(
                          color: trusted ? _dark : Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid ?? 'unknown')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final data = snap.data?.data();
                final barangay = data?['barangay']?.toString();
                final muni = data?['municipality']?.toString() ?? '';
                final prov = data?['province']?.toString() ?? '';
                final readable = [
                  barangay,
                  muni,
                  prov,
                ].where((s) => s != null && s.isNotEmpty).join(', ');

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Saved Location',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      readable.isNotEmpty ? readable : 'Not set',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TextButton(
                      onPressed: () => _editLocation(data),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Edit Location',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),

            Text(
              user?.email ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 28),

            // ---- Quick links to the two real features above (mirrors ----
            // ---- how the hamburger menu items work, just more discoverable) ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _profileLinkTile(
                    icon: Icons.settings_outlined,
                    label: 'Account Settings',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BuyerSettingsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _profileLinkTile(
                    icon: Icons.support_agent_outlined,
                    label: 'Help & Support',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BuyerSupportScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileLinkTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: _dark),
        title: Text(
          label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
