import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';

/// One option on a Profile tab (My Reviews, Notifications, Account
/// Settings...): icon, label, chevron. Shared by the Buyer and Farmer
/// profiles so their option lists look the same.
class ProfileLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ProfileLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: AppTheme.dark),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

/// The foot of a Profile tab: a divider, Log Out, then the app version.
/// [onLogout] is the role's own log-out (it asks for confirmation first).
class ProfileFooter extends StatelessWidget {
  final VoidCallback onLogout;

  const ProfileFooter({super.key, required this.onLogout});

  // Read once for the app's lifetime — it cannot change while running.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 1, color: Colors.grey[300]),
        const SizedBox(height: 6),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text(
            'Log Out',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.redAccent,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onTap: onLogout,
        ),
        const SizedBox(height: 10),
        // The real version from the installed build; nothing is shown
        // until (or unless) it can be read.
        FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? '';
            if (version.isEmpty) return const SizedBox(height: 16);
            return Text(
              'AgriTrade+ • Version $version',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            );
          },
        ),
      ],
    );
  }
}
