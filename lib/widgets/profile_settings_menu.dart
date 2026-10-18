import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screen/manage_account_screen.dart';
import '../screen/notification_preferences_screen.dart';
import 'page_header.dart';
import '../l10n/tr.dart';

/// The settings (gear) menu beside the farmer's Profile title:
///
///   [Share My Store]   Notification Settings   Manage Account
///   Help & Support   ─────   Log Out (red)
///
/// (The buyer's Profile lists the same options on the page itself, in
/// labelled groups.) Manage Account is one screen for both roles; Help &
/// Support and Log Out are the role's own ([onHelp], [onLogout]).
class ProfileSettingsMenu extends StatelessWidget {
  /// Farmers only: shares their store. Null leaves the item out.
  final VoidCallback? onShareStore;
  final VoidCallback onHelp;
  final VoidCallback onLogout;

  const ProfileSettingsMenu({
    super.key,
    this.onShareStore,
    required this.onHelp,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    // Compact rows: a small icon, then small text.
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color color = Colors.black87,
    }) => PopupMenuItem(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );

    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return PopupMenuButton<String>(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined, color: PageHeader.titleColor),
      // A small floating panel that opens just below the icon.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      // White, rounded, shadowed: the app-wide popup menu look (AppTheme).
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onSelected: (value) {
        switch (value) {
          case 'share':
            onShareStore?.call();
          case 'notifications':
            open(const NotificationPreferencesScreen());
          case 'manage':
            open(const ManageAccountScreen());
          case 'help':
            onHelp();
          case 'logout':
            onLogout();
        }
      },
      itemBuilder: (context) => [
        if (onShareStore != null)
          item('share', Icons.share_outlined, t.shareMyStore),
        item(
          'notifications',
          Icons.notifications_none_rounded,
          t.notificationSettings,
        ),
        item('manage', Icons.manage_accounts_outlined, t.manageAccount),
        item('help', Icons.help_outline, t.helpSupport),
        const PopupMenuDivider(height: 9),
        item('logout', Icons.logout, t.logOut, color: const Color(0xFFD32F2F)),
      ],
    );
  }
}
