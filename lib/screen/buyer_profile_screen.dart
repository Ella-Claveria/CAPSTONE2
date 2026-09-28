import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/open_in_maps_button.dart';
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

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
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
            title: Text('Account Settings', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
        ),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline, color: _dark),
            title: Text('Change Password', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
        ),
        const PopupMenuItem(
          value: 'help',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.help_outline, color: _dark),
            title: Text('Help & Support', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Colors.redAccent),
            title: Text('Log Out', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Colors.redAccent)),
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
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid ?? '').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final photoUrl = data?['photoUrl']?.toString() ?? user?.photoURL;
        final ImageProvider? imageProvider =
            (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null;

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
                child: imageProvider == null ? const Icon(Icons.person, color: _dark, size: 52) : null,
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
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),

            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(user?.uid ?? 'unknown').snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data();
                final barangay = data?['barangay']?.toString();
                final muni = data?['municipality']?.toString() ?? '';
                final prov = data?['province']?.toString() ?? '';
                final latitude = (data?['latitude'] as num?)?.toDouble();
                final longitude = (data?['longitude'] as num?)?.toDouble();

                // Legacy accounts (registered before buyers could pick any
                // location) still have a Laurel barangay on file — show
                // that. A current buyer instead only has a map pin, so
                // there's no place name to show, just "My Location" with a
                // tap-to-view-on-map affordance.
                if (barangay != null && barangay.isNotEmpty) {
                  final location = [barangay, muni, prov].where((s) => s.isNotEmpty).join(', ');
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined, size: 15, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(location, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    ],
                  );
                }
                if (latitude != null && longitude != null) {
                  return InkWell(
                    onTap: () => MapsLauncher.open(context, latitude: latitude, longitude: longitude),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined, size: 15, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('My Location', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
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
                      MaterialPageRoute(builder: (_) => const BuyerSettingsScreen()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _profileLinkTile(
                    icon: Icons.support_agent_outlined,
                    label: 'Help & Support',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BuyerSupportScreen()),
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

  Widget _profileLinkTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: _dark),
        title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
