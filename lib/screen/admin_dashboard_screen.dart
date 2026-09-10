import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'verification_queue_view.dart';
import 'moderation_queue_view.dart';
import '../widgets/agritrade_text.dart';
import '../data/laurel_barangays.dart';
import '../services/connectivity_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/change_password_dialog.dart';

// ============================================================
// THEME — a small self-contained palette system (dark + light)
// so this screen doesn't depend on the app's global ThemeData.
// ============================================================
class AdminPalette {
  final bool isDark;
  final Color bg;
  final Color sidebarBg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconInactive;
  final Color green;
  final Color greenBg;
  final Color red;
  final Color redBg;
  final Color amber;
  final Color amberBg;
  final Color blue;
  final Color blueBg;

  const AdminPalette({
    required this.isDark,
    required this.bg,
    required this.sidebarBg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconInactive,
    required this.green,
    required this.greenBg,
    required this.red,
    required this.redBg,
    required this.amber,
    required this.amberBg,
    required this.blue,
    required this.blueBg,
  });

  static const dark = AdminPalette(
    isDark: true,
    bg: Color(0xFF0E1013),
    sidebarBg: Color(0xFF000000),
    surface: Color(0xFF181B20),
    surfaceAlt: Color(0xFF20242B),
    border: Color(0xFF2A2E36),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF9AA1AC),
    textMuted: Color(0xFF5B616C),
    iconInactive: Colors.white70,
    green: Color(0xFF22C55E),
    greenBg: Color(0x2922C55E),
    red: Color(0xFFF87171),
    redBg: Color(0x29F87171),
    amber: Color(0xFFFBBF24),
    amberBg: Color(0x29FBBF24),
    blue: Color(0xFF60A5FA),
    blueBg: Color(0x2960A5FA),
  );

  static const light = AdminPalette(
    isDark: false,
    bg: Color(0xFFF4F5F7),
    sidebarBg: Colors.white,
    surface: Colors.white,
    surfaceAlt: Color(0xFFF0F1F4),
    border: Color(0xFFE3E5E9),
    textPrimary: Color(0xFF14171C),
    textSecondary: Color(0xFF676D78),
    textMuted: Color(0xFFA0A5AF),
    iconInactive: Color(0xFF52575F),
    green: Color(0xFF16A34A),
    greenBg: Color(0x2016A34A),
    red: Color(0xFFDC2626),
    redBg: Color(0x20DC2626),
    amber: Color(0xFFD97706),
    amberBg: Color(0x20D97706),
    blue: Color(0xFF2563EB),
    blueBg: Color(0x202563EB),
  );
}

/// Provides the current [AdminPalette] + a theme-toggle callback to the
/// whole admin subtree, so any descendant widget can read
/// `_AdminThemeScope.of(context).palette` without prop-drilling.
class _AdminThemeScope extends InheritedWidget {
  final AdminPalette palette;
  final VoidCallback onToggleTheme;

  const _AdminThemeScope({
    required this.palette,
    required this.onToggleTheme,
    required super.child,
  });

  bool get isDark => palette.isDark;

  static _AdminThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_AdminThemeScope>();
    assert(scope != null, '_AdminThemeScope not found above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_AdminThemeScope oldWidget) =>
      palette.isDark != oldWidget.palette.isDark;
}

// ============================================================
// NAV ITEM MODEL
// ============================================================
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

const List<_NavItem> _navItems = [
  _NavItem(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Analytics Dashboard'),
  _NavItem(Icons.map_outlined, Icons.map_rounded, 'Demand Heatmap'),
  _NavItem(Icons.verified_user_outlined, Icons.verified_user_rounded, 'Verification Queue'),
  _NavItem(Icons.gavel_outlined, Icons.gavel_rounded, 'Moderation Center'),
  _NavItem(Icons.price_change_outlined, Icons.price_change_rounded, 'Price Management'),
];

// ============================================================
// ROOT SCREEN
// ============================================================
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  bool _railExpanded = false; // collapsed (icon-only) by default, like the reference
  bool _isDark = true; // default to dark mode

  // TODO: persist this choice (e.g. SharedPreferences) so it survives app
  // restarts, and/or seed it from the platform brightness on first launch.
  void _toggleTheme() => setState(() => _isDark = !_isDark);

  void _goTo(int index) => setState(() => _selectedIndex = index);
  void _toggleRail() => setState(() => _railExpanded = !_railExpanded);

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: ${e.toString()}')),
        );
      }
    }
  }

  late final List<Widget> _pages = [
    _AnalyticsDashboardView(onNavigate: _goTo),
    const _DemandHeatmapView(),
    const VerificationQueueView(),
    const ModerationQueueView(),
    const _PriceManagementView(),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _isDark ? AdminPalette.dark : AdminPalette.light;

    return _AdminThemeScope(
      palette: palette,
      onToggleTheme: _toggleTheme,
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Row(
          children: [
            _AdminSidebar(
              expanded: _railExpanded,
              selectedIndex: _selectedIndex,
              onToggleExpand: _toggleRail,
              onDestinationSelected: _goTo,
              onLogout: _logout,
            ),
            Container(width: 1, color: palette.border),
            Expanded(
              child: Column(
                children: [
                  _AdminTopHeader(isDesktop: MediaQuery.of(context).size.width >= 800),
                  Container(height: 1, color: palette.border),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(_selectedIndex),
                        child: _pages[_selectedIndex],
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
}

// ============================================================
// TOP HEADER — search, theme toggle, and notification bell.
// Logout lives on the sidebar's avatar menu, so this stays lean.
// ============================================================
class _AdminTopHeader extends StatelessWidget {
  final bool isDesktop;
  const _AdminTopHeader({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const AgriTradeText(fontSize: 22),
          const Spacer(),
          if (isDesktop)
            Container(
              width: 260,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                style: TextStyle(color: c.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search records...',
                  hintStyle: TextStyle(color: c.textSecondary),
                  prefixIcon: Icon(Icons.search, size: 20, color: c.textSecondary),
                  filled: true,
                  fillColor: c.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          const _ThemeToggleButton(),
          const SizedBox(width: 8),
          const _NotificationBell(),
        ],
      ),
    );
  }
}

/// Sun / moon toggle that flips the whole admin shell between the
/// dark and light [AdminPalette].
class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    final scope = _AdminThemeScope.of(context);
    final c = scope.palette;
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceAlt),
      child: IconButton(
        tooltip: c.isDark ? 'Switch to light mode' : 'Switch to dark mode',
        icon: Icon(
          c.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          color: c.textSecondary,
        ),
        onPressed: scope.onToggleTheme,
      ),
    );
  }
}

// ============================================================
// NOTIFICATIONS — bell with unread badge + dropdown panel.
// Data is empty for now; the read/unread + rendering logic is
// fully wired so it lights up the moment real data streams in.
// ============================================================
class _AdminNotification {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final bool read;
  const _AdminNotification({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
  }) : read = false;
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  // TODO: replace with a live stream from an `admin_notifications`
  // Firestore collection (e.g. new verification requests, new reports).
  static const List<_AdminNotification> _notifications = [];

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    final unreadCount = _notifications.where((n) => !n.read).length;

    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      color: c.surface,
      elevation: 6,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Notifications',
                          style: TextStyle(
                              color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                      if (unreadCount > 0)
                        Text('$unreadCount new',
                            style: TextStyle(
                                color: c.green, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                if (_notifications.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none_rounded, size: 30, color: c.textMuted),
                        const SizedBox(height: 10),
                        Text('No notifications yet',
                            style: TextStyle(
                                color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          "You'll see verification requests, flagged\nreports, and system alerts here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textMuted, fontSize: 11.5, height: 1.4),
                        ),
                      ],
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _notifications.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                      itemBuilder: (context, index) {
                        final n = _notifications[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(n.icon, size: 20, color: n.read ? c.textMuted : c.green),
                          title: Text(n.title,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13,
                                  fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                          subtitle: Text(n.subtitle,
                              style: TextStyle(color: c.textSecondary, fontSize: 12)),
                          trailing: Text(n.time, style: TextStyle(color: c.textMuted, fontSize: 11)),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceAlt),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_outlined, color: c.textSecondary, size: 22),
            if (unreadCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surfaceAlt, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SIDEBAR — collapsible, icon-only by default (ChatGPT-style),
// adapts to dark/light, logo at top, nav icons in the middle,
// user avatar (with logout menu) pinned to the bottom.
// ============================================================
class _AdminSidebar extends StatelessWidget {
  final bool expanded;
  final int selectedIndex;
  final VoidCallback onToggleExpand;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLogout;

  const _AdminSidebar({
    required this.expanded,
    required this.selectedIndex,
    required this.onToggleExpand,
    required this.onDestinationSelected,
    required this.onLogout,
  });

  static const double _collapsedWidth = 72;
  static const double _expandedWidth = 240;

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: expanded ? _expandedWidth : _collapsedWidth,
      color: c.sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _SidebarToggleButton(expanded: expanded, onTap: onToggleExpand),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _navItems.length,
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final selected = index == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _SidebarNavTile(
                      icon: selected ? item.selectedIcon : item.icon,
                      label: item.label,
                      selected: selected,
                      expanded: expanded,
                      onTap: () => onDestinationSelected(index),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(color: c.border, height: 1),
            ),
            const SizedBox(height: 12),
            _SidebarAvatarMenu(expanded: expanded, onLogout: onLogout),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _SidebarToggleButton({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: expanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
        children: [
          if (expanded)
            Row(
              children: [
                Icon(Icons.eco_rounded, color: c.green, size: 22),
                const SizedBox(width: 8),
                Text('AgriTrade+',
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          Tooltip(
            message: expanded ? 'Collapse' : 'Expand',
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: c.iconInactive,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    final iconColor = selected ? c.green : c.iconInactive;
    final bgColor = selected ? c.greenBg : Colors.transparent;

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: expanded
              ? Row(
                  children: [
                    Icon(icon, color: iconColor, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? c.green : c.iconInactive,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                )
              : Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );

    if (expanded) return tile;
    return Tooltip(message: label, child: tile);
  }
}

class _SidebarAvatarMenu extends StatelessWidget {
  final bool expanded;
  final VoidCallback onLogout;
  const _SidebarAvatarMenu({required this.expanded, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final scope = _AdminThemeScope.of(context);
    final c = scope.palette;

    // TODO: replace initials/name with the authenticated admin's real profile
    // data (e.g. FirebaseAuth.instance.currentUser / a Firestore admins doc).
    const initials = 'AD';
    const displayName = 'Admin';

    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: c.green,
      child: const Text(initials,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
    );

    return PopupMenuButton<String>(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      tooltip: 'Account',
      offset: const Offset(56, 0),
      onSelected: (value) {
        if (value == 'logout') onLogout();
        if (value == 'theme') scope.onToggleTheme();
        if (value == 'password') showChangePasswordDialog(context);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('Signed in as Admin',
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'password',
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: c.iconInactive),
              const SizedBox(width: 10),
              Text('Change Password', style: TextStyle(color: c.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'theme',
          child: Row(
            children: [
              Icon(c.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  size: 18, color: c.iconInactive),
              const SizedBox(width: 10),
              Text(c.isDark ? 'Light mode' : 'Dark mode', style: TextStyle(color: c.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: c.red),
              const SizedBox(width: 10),
              Text('Logout', style: TextStyle(color: c.red)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
        child: expanded
            ? Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Icon(Icons.more_vert, color: c.textMuted, size: 18),
                ],
              )
            : Center(child: avatar),
      ),
    );
  }
}

// ============================================================
// SMALL REUSABLE PIECES (cards, badges, buttons)
// ============================================================

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final IconData icon;
  final Color Function(AdminPalette c) iconColor;
  final Color Function(AdminPalette c) iconBg;
  final bool isEmpty;

  const _StatCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: isEmpty ? c.surfaceAlt : iconBg(c), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: isEmpty ? c.textMuted : iconColor(c)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: TextStyle(
                  color: isEmpty ? c.textMuted : c.textPrimary, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(delta,
              style: TextStyle(
                  color: isEmpty ? c.textMuted : c.green, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;

  const _StatusBadge({required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: c.green,
          foregroundColor: c.isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: c.textPrimary),
      label: Text(label, style: TextStyle(color: c.textPrimary)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Generic empty-state block reused across dashboard sections.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 34, color: c.textMuted),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of a section while its Firestore stream's first snapshot
/// hasn't arrived yet — cards must never flash "0" / empty before real data
/// is known (see requirement: no fallback values while still loading).
class _AdminLoadingSpinner extends StatelessWidget {
  const _AdminLoadingSpinner();

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator(color: c.green)),
    );
  }
}

/// Shown when a dashboard stream errors out (e.g. permission denied,
/// offline with nothing cached) instead of silently rendering empty data.
class _AdminStreamError extends StatelessWidget {
  static const String message = 'Could not load this data. Check your connection and try again.';
  const _AdminStreamError();

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: c.red, size: 32),
            const SizedBox(height: 10),
            Text(message, style: TextStyle(color: c.textSecondary, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ANALYTICS DASHBOARD (main admin landing view)
// Wired to live Firestore collections: users, verificationDocs,
// reports, orders, and market_prices.
// ============================================================

class _VerificationRow {
  final String uid;
  final String farmerId;
  final String fullName;
  final String category; // shows the applicant's barangay
  final String dateSubmitted;
  final String status; // Pending, Approved, Rejected
  const _VerificationRow(
      this.uid, this.farmerId, this.fullName, this.category, this.dateSubmitted, this.status);
}

class _CommodityPrice {
  final String name;
  final String price;
  final String changePct;
  final bool isUp;
  final String updatedAgo;
  const _CommodityPrice(this.name, this.price, this.changePct, this.isUp, this.updatedAgo);
}

class _AnalyticsDashboardView extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const _AnalyticsDashboardView({required this.onNavigate});

  static String _statusLabel(dynamic raw) {
    final status = (raw ?? 'pending').toString();
    if (status.isEmpty) return 'Pending';
    return status[0].toUpperCase() + status.substring(1);
  }

  List<_VerificationRow> _recentVerifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> verifDocs,
    Map<String, Map<String, dynamic>> usersByUid,
  ) {
    final sorted = [...verifDocs]..sort((a, b) {
        final at = a.data()['submittedAt'] as Timestamp?;
        final bt = b.data()['submittedAt'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
      });

    return sorted.take(5).map((doc) {
      final data = doc.data();
      final userId = (data['userId'] ?? doc.id).toString();
      final userDoc = usersByUid[userId];
      // The verificationDocs record's own fullName wins when present (it's
      // the name the farmer typed at submission time); otherwise fall back
      // to their live user profile — this is what actually fixes "Unknown
      // Farmer" for legacy records that predate `fullName` being stored on
      // the verification doc itself.
      final fullName = _firstNonEmpty([
        data['fullName'],
        userDoc?['fullName'],
        userDoc?['name'],
      ]) ?? 'Unknown Farmer';
      final barangay = _firstNonEmpty([userDoc?['barangay']]) ?? '—';
      final submittedAt = data['submittedAt'] as Timestamp?;
      final dateSubmitted = submittedAt != null
          ? DateFormat('MMM d, y').format(submittedAt.toDate())
          : '—';
      return _VerificationRow(
        userId,
        userId.length > 8 ? userId.substring(0, 8) : userId,
        fullName,
        barangay,
        dateSubmitted,
        _statusLabel(data['status']),
      );
    }).toList();
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  num _platformTransactionTotal(List<QueryDocumentSnapshot<Map<String, dynamic>>> orders) {
    num total = 0;
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') continue;
      final raw = data['total'];
      total += raw is num ? raw : num.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return total;
  }

  ({String name, num revenue, num quantity})? _topSellingProduct(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
  ) {
    final revenueByProduct = <String, num>{};
    final qtyByProduct = <String, num>{};
    for (final doc in orders) {
      final data = doc.data();
      if ((data['status'] ?? '').toString().toLowerCase() != 'completed') continue;
      final name = (data['productName'] ?? '').toString();
      if (name.isEmpty) continue;
      final total = data['total'];
      final qty = data['quantity'];
      revenueByProduct[name] = (revenueByProduct[name] ?? 0) +
          (total is num ? total : num.tryParse(total?.toString() ?? '') ?? 0);
      qtyByProduct[name] = (qtyByProduct[name] ?? 0) +
          (qty is num ? qty : num.tryParse(qty?.toString() ?? '') ?? 0);
    }
    if (revenueByProduct.isEmpty) return null;

    final top = revenueByProduct.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (name: top.key, revenue: top.value, quantity: qtyByProduct[top.key] ?? 0);
  }

  List<_CommodityPrice> _commodityPrices(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return docs.map((doc) {
      final data = doc.data();
      final name = (data['name'] ?? doc.id).toString();
      final current = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
      final previous = (data['previousBaselinePrice'] as num?)?.toDouble();
      final hasPrevious = previous != null && previous > 0;
      final changePct = hasPrevious ? ((current - previous) / previous) * 100 : 0.0;
      return _CommodityPrice(
        name,
        formatPeso(current),
        hasPrevious ? '${changePct.abs().toStringAsFixed(1)}%' : 'New',
        changePct >= 0,
        timeAgo(data['updatedAt'] as Timestamp?),
      );
    }).toList();
  }

  Color _statusColor(AdminPalette c, String s) {
    switch (s) {
      case 'Approved':
        return c.green;
      case 'Rejected':
        return c.red;
      default:
        return c.amber;
    }
  }

  Color _statusBg(AdminPalette c, String s) {
    switch (s) {
      case 'Approved':
        return c.greenBg;
      case 'Rejected':
        return c.redBg;
      default:
        return c.amberBg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('verificationDocs').snapshots(),
          builder: (context, verifSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('reports')
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, reportsSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('orders').snapshots(),
                  builder: (context, ordersSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance.collection('market_prices').snapshots(),
                      builder: (context, pricesSnap) {
                        final snapshots = [usersSnap, verifSnap, reportsSnap, ordersSnap, pricesSnap];
                        if (snapshots.any((s) => s.hasError)) {
                          return const _AdminStreamError();
                        }
                        // Every stream must have delivered its first snapshot before
                        // any KPI renders — otherwise a card would briefly show "0"
                        // while Firestore is still loading, which reads as real data.
                        if (snapshots.any((s) => !s.hasData)) {
                          return const _AdminLoadingSpinner();
                        }

                        final userDocs = usersSnap.data!.docs;
                        final usersByUid = <String, Map<String, dynamic>>{
                          for (final doc in userDocs) doc.id: doc.data(),
                        };
                        // Marketplace users only — Admin accounts aren't part of
                        // the Farmer/Buyer user base this KPI reports on.
                        final farmerCount = userDocs.where((d) => d.data()['role'] == 'farmer').length;
                        final buyerCount = userDocs.where((d) => d.data()['role'] == 'buyer').length;
                        final totalUsers = farmerCount + buyerCount;

                        final verifDocs = verifSnap.data!.docs;
                        // Sourced from `users` (role + approvalStatus), matching the
                        // field the approval action itself writes to — this stays
                        // accurate even for legacy farmers who have a pending status
                        // but never went through the verificationDocs submission flow
                        // (verificationDocs is still the right source for *which*
                        // submitted applications are actionable, in the queue below).
                        final pendingVerifications = userDocs
                            .where((d) =>
                                d.data()['role'] == 'farmer' && d.data()['approvalStatus'] == 'pending')
                            .length;
                        final recentVerifications = _recentVerifications(verifDocs, usersByUid);

                        final flaggedReports = reportsSnap.data!.docs.length;

                        final orders = ordersSnap.data!.docs;
                        final totalTransactionValue = _platformTransactionTotal(orders);
                        final topProduct = _topSellingProduct(orders);

                        final prices = _commodityPrices(pricesSnap.data!.docs);

                        return _buildBody(
                          context,
                          c,
                          totalUsers: totalUsers,
                          farmerCount: farmerCount,
                          buyerCount: buyerCount,
                          pendingVerifications: pendingVerifications,
                          flaggedReports: flaggedReports,
                          totalTransactionValue: totalTransactionValue,
                          verifications: recentVerifications,
                          prices: prices,
                          topProduct: topProduct,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AdminPalette c, {
    required int totalUsers,
    required int farmerCount,
    required int buyerCount,
    required int pendingVerifications,
    required int flaggedReports,
    required num totalTransactionValue,
    required List<_VerificationRow> verifications,
    required List<_CommodityPrice> prices,
    required ({String name, num revenue, num quantity})? topProduct,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- KPI ROW ----
          LayoutBuilder(builder: (context, constraints) {
            final cards = [
              _StatCard(
                label: 'Total Users',
                value: '$totalUsers',
                delta: '$farmerCount farmers · $buyerCount buyers',
                icon: Icons.groups_2_outlined,
                iconColor: (c) => c.blue,
                iconBg: (c) => c.blueBg,
                isEmpty: totalUsers == 0,
              ),
              _StatCard(
                label: 'Pending Verifications',
                value: '$pendingVerifications',
                delta: 'Awaiting admin review',
                icon: Icons.fact_check_outlined,
                iconColor: (c) => c.amber,
                iconBg: (c) => c.amberBg,
                isEmpty: pendingVerifications == 0,
              ),
              _StatCard(
                label: 'Flagged Reports',
                value: '$flaggedReports',
                delta: 'Unresolved',
                icon: Icons.flag_outlined,
                iconColor: (c) => c.red,
                iconBg: (c) => c.redBg,
                isEmpty: flaggedReports == 0,
              ),
              _StatCard(
                label: 'Total Transaction Value',
                value: formatPeso(totalTransactionValue),
                delta: 'From completed orders',
                icon: Icons.receipt_long_outlined,
                iconColor: (c) => c.green,
                iconBg: (c) => c.greenBg,
                isEmpty: totalTransactionValue == 0,
              ),
            ];
            final isNarrow = constraints.maxWidth < 900;
            return GridView.count(
              crossAxisCount: isNarrow ? 2 : 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: isNarrow ? 1.6 : 1.5,
              children: cards,
            );
          }),

          const SizedBox(height: 20),

          // ---- QUICK ACTIONS ----
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _QuickActionButton(
                icon: Icons.verified_user_outlined,
                label: 'Verify Farmers',
                filled: true,
                onPressed: () => onNavigate(2),
              ),
              _QuickActionButton(
                icon: Icons.gavel_outlined,
                label: 'Review Reports',
                onPressed: () => onNavigate(3),
              ),
              _QuickActionButton(
                icon: Icons.map_outlined,
                label: 'Demand Heatmap',
                onPressed: () => onNavigate(1),
              ),
              _QuickActionButton(
                icon: Icons.price_change_outlined,
                label: 'Manage Prices',
                onPressed: () => onNavigate(4),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ---- RECENT VERIFICATION REQUESTS TABLE ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent Verification Requests',
                            style: TextStyle(
                                color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Latest farmer & livestock raiser applications',
                            style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      ],
                    ),
                    TextButton(
                      onPressed: () => onNavigate(2),
                      child: Text('View all', style: TextStyle(color: c.green)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (verifications.isEmpty)
                  const _EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No verification requests yet',
                    subtitle: 'New farmer applications will appear here once submitted.',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
                      dataRowColor: WidgetStateProperty.all(Colors.transparent),
                      columnSpacing: 32,
                      horizontalMargin: 12,
                      headingTextStyle:
                          TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
                      columns: const [
                        DataColumn(label: Text('Farmer ID')),
                        DataColumn(label: Text('Full Name')),
                        DataColumn(label: Text('Barangay')),
                        DataColumn(label: Text('Date Submitted')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: verifications
                          .map((v) => DataRow(cells: [
                                DataCell(Text(v.farmerId)),
                                DataCell(Text(v.fullName)),
                                DataCell(Text(v.category)),
                                DataCell(Text(v.dateSubmitted)),
                                DataCell(_StatusBadge(
                                    text: v.status,
                                    color: _statusColor(c, v.status),
                                    bg: _statusBg(c, v.status))),
                                DataCell(IconButton(
                                  tooltip: 'View verification details',
                                  icon: Icon(Icons.visibility_outlined, size: 18, color: c.textSecondary),
                                  onPressed: () => showFarmerVerificationDetails(context, uid: v.uid),
                                )),
                              ]))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ---- BEST-SELLING PRODUCT (PLATFORM-WIDE) ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 18, color: c.amber),
                    const SizedBox(width: 8),
                    Text('Best-Selling Product',
                        style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Platform-wide, by completed-order revenue',
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
                const SizedBox(height: 14),
                if (topProduct == null)
                  const _EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No completed sales yet',
                    subtitle: 'The top-selling product will appear here once orders complete.',
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(topProduct.name,
                                style: TextStyle(
                                    color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${topProduct.quantity.toStringAsFixed(0)} kg sold across the platform',
                                style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Text(formatPeso(topProduct.revenue),
                          style: TextStyle(color: c.green, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ---- LIVE COMMODITY / CURRENT MARKET AVERAGE PRICES ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Live Commodity Prices',
                            style: TextStyle(
                                color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Current Market Average — Laurel, Batangas',
                            style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      ],
                    ),
                    TextButton(
                      onPressed: () => onNavigate(4),
                      child: Text('Manage prices', style: TextStyle(color: c.green)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (prices.isEmpty)
                  const _EmptyState(
                    icon: Icons.price_change_outlined,
                    title: 'No commodity price data yet',
                    subtitle: 'Prices will populate once listings and market data are recorded.',
                  )
                else
                  SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: prices.length,
                      itemBuilder: (context, index) {
                        final p = prices[index];
                        return Container(
                          width: 170,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: TextStyle(
                                      color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text(p.price,
                                  style: TextStyle(
                                      color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(p.isUp ? Icons.arrow_upward : Icons.arrow_downward,
                                      size: 12, color: p.isUp ? c.green : c.red),
                                  const SizedBox(width: 2),
                                  Text(p.changePct,
                                      style: TextStyle(
                                          color: p.isUp ? c.green : c.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: c.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(p.updatedAgo, style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DEMAND HEATMAP
// ============================================================

class _BarangayDemand {
  final String barangay;
  final double lat;
  final double lng;
  final int orderCount;
  final int farmerCount;
  const _BarangayDemand(this.barangay, this.lat, this.lng, this.orderCount, this.farmerCount);
}

List<_BarangayDemand> _computeBarangayDemand(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> completedOrders,
) {
  // Approved farmers only — their barangay is the geospatial anchor,
  // since neither farmers nor orders carry real lat/lng today.
  final barangayByFarmerUid = <String, String>{};
  for (final doc in users) {
    final data = doc.data();
    if ((data['role'] ?? '') != 'farmer') continue;
    if ((data['approvalStatus'] ?? '') != 'approved') continue;
    final barangay = (data['barangay'] ?? '').toString();
    if (barangay.isEmpty) continue;
    barangayByFarmerUid[doc.id] = barangay;
  }

  final orderCountByBarangay = <String, int>{};
  final farmersByBarangay = <String, Set<String>>{};
  for (final doc in completedOrders) {
    final sellerId = (doc.data()['sellerId'] ?? '').toString();
    final barangay = barangayByFarmerUid[sellerId];
    if (barangay == null) continue;
    orderCountByBarangay[barangay] = (orderCountByBarangay[barangay] ?? 0) + 1;
    farmersByBarangay.putIfAbsent(barangay, () => {}).add(sellerId);
  }

  return kLaurelBarangayLocations
      .map((loc) => _BarangayDemand(
            loc.name,
            loc.lat,
            loc.lng,
            orderCountByBarangay[loc.name] ?? 0,
            farmersByBarangay[loc.name]?.length ?? 0,
          ))
      .toList();
}

List<MapEntry<String, int>> _topSearchQueries(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> searchDocs,
) {
  final counts = <String, int>{};
  for (final doc in searchDocs) {
    final query = (doc.data()['query'] ?? '').toString().trim().toLowerCase();
    if (query.isEmpty) continue;
    counts[query] = (counts[query] ?? 0) + 1;
  }
  final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(8).toList();
}

class _DemandHeatmapView extends StatefulWidget {
  const _DemandHeatmapView();

  @override
  State<_DemandHeatmapView> createState() => _DemandHeatmapViewState();
}

class _DemandHeatmapViewState extends State<_DemandHeatmapView> {
  static const _center = LatLng(kLaurelCenterLat, kLaurelCenterLng);

  Set<Circle> _buildCircles(List<_BarangayDemand> demand) {
    final maxCount = demand.fold<int>(0, (a, d) => d.orderCount > a ? d.orderCount : a);
    return demand.map((d) {
      final intensity = maxCount == 0 ? 0.0 : d.orderCount / maxCount;
      final color = d.orderCount == 0
          ? Colors.grey
          : Color.lerp(Colors.amber, Colors.red, intensity) ?? Colors.amber;
      final radius = 220.0 + intensity * 900.0;
      return Circle(
        circleId: CircleId(d.barangay),
        center: LatLng(d.lat, d.lng),
        radius: radius,
        fillColor: color.withValues(alpha: d.orderCount == 0 ? 0.08 : 0.35),
        strokeColor: color,
        strokeWidth: d.orderCount == 0 ? 1 : 2,
        consumeTapEvents: true,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${d.barangay}: ${d.orderCount} completed order(s) across ${d.farmerCount} farmer(s).',
            ),
          ),
        ),
      );
    }).toSet();
  }

  String _buildCsv(List<_BarangayDemand> demand, List<MapEntry<String, int>> topSearches) {
    final buffer = StringBuffer();
    buffer.writeln('AgriTrade+ Demand Report — ${DateFormat('MMM d, y – h:mm a').format(DateTime.now())}');
    buffer.writeln();
    buffer.writeln('Barangay,Completed Orders,Approved Farmers');
    for (final d in demand) {
      buffer.writeln('${d.barangay},${d.orderCount},${d.farmerCount}');
    }
    buffer.writeln();
    buffer.writeln('Top Buyer Searches,Count');
    for (final e in topSearches) {
      buffer.writeln('${e.key},${e.value}');
    }
    return buffer.toString();
  }

  Future<void> _exportReport(
    BuildContext context,
    List<_BarangayDemand> demand,
    List<MapEntry<String, int>> topSearches,
  ) async {
    await Clipboard.setData(ClipboardData(text: _buildCsv(demand, topSearches)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard — paste into a spreadsheet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('status', isEqualTo: 'completed')
              .snapshots(),
          builder: (context, ordersSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('searchEvents').snapshots(),
              builder: (context, searchSnap) {
                if (usersSnap.hasError || ordersSnap.hasError || searchSnap.hasError) {
                  return const _AdminStreamError();
                }
                if (!usersSnap.hasData || !ordersSnap.hasData || !searchSnap.hasData) {
                  return const _AdminLoadingSpinner();
                }

                final demand = _computeBarangayDemand(usersSnap.data!.docs, ordersSnap.data!.docs);
                final rankedDemand = [...demand]..sort((a, b) => b.orderCount.compareTo(a.orderCount));
                final topSearches = _topSearchQueries(searchSnap.data!.docs);

                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Market Demand Forecast',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold, color: c.textPrimary)),
                          _QuickActionButton(
                            icon: Icons.download,
                            label: 'Export Report',
                            filled: true,
                            onPressed: () => _exportReport(context, demand, topSearches),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Barangay circles are sized by completed orders per approved farmer\'s barangay. '
                        'Marker positions are illustrative, not surveyed coordinates.',
                        style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: GoogleMap(
                                  initialCameraPosition: const CameraPosition(target: _center, zoom: 12.5),
                                  circles: _buildCircles(demand),
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _DemandSidePanel(
                                      title: 'Highest Demand Barangays',
                                      icon: Icons.local_fire_department_outlined,
                                      emptyText: 'No completed orders yet.',
                                      rows: rankedDemand
                                          .where((d) => d.orderCount > 0)
                                          .take(6)
                                          .map((d) => '${d.barangay} — ${d.orderCount} order(s)')
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: _DemandSidePanel(
                                      title: 'Top Buyer Searches',
                                      icon: Icons.search,
                                      emptyText: 'No search activity logged yet.',
                                      rows: topSearches
                                          .map((e) => '${e.key} — ${e.value} search(es)')
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DemandSidePanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyText;
  final List<String> rows;

  const _DemandSidePanel({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Expanded(
              child: Center(
                child: Text(emptyText,
                    style: TextStyle(color: c.textMuted, fontSize: 12), textAlign: TextAlign.center),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(rows[index], style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// PRICE MANAGEMENT — bound to the `market_prices` collection.
// "Live Market Average" is computed on the fly from current
// `products` listings; "Baseline Price" is what the admin sets
// here and is meant to feed the price-recommendation system.
// ============================================================

class _PriceManagementView extends StatelessWidget {
  const _PriceManagementView();

  Future<void> _openBaselineDialog(
    BuildContext context, {
    String? commodityId,
    String? name,
    double? price,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BaselinePriceDialog(
        commodityId: commodityId,
        initialName: name,
        initialPrice: price,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Baseline price saved.')),
      );
    }
  }

  Future<void> _deleteBaseline(BuildContext context, String commodityId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove baseline price?'),
        content: Text('This removes the official baseline for "$name". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!await ConnectivityService.instance.checkNow()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      }
      return;
    }
    await FirebaseFirestore.instance.collection('market_prices').doc(commodityId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final c = _AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Market Average Management',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.textPrimary)),
              Row(
                children: [
                  _QuickActionButton(
                    icon: Icons.refresh,
                    label: 'Refresh All',
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Prices sync live — nothing to refresh.')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _QuickActionButton(
                    icon: Icons.add,
                    label: 'Add Commodity',
                    filled: true,
                    onPressed: () => _openBaselineDialog(context),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('market_prices').orderBy('name').snapshots(),
              builder: (context, pricesSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('products').snapshots(),
                  builder: (context, productsSnap) {
                    if (pricesSnap.hasError || productsSnap.hasError) {
                      return const _AdminStreamError();
                    }
                    if (!pricesSnap.hasData || !productsSnap.hasData) {
                      return const _AdminLoadingSpinner();
                    }

                    final priceDocs = pricesSnap.data!.docs;
                    final products = productsSnap.data!.docs;

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.border),
                      ),
                      child: priceDocs.isEmpty
                          ? const _EmptyState(
                              icon: Icons.price_change_outlined,
                              title: 'No baseline prices set yet',
                              subtitle: 'Set official commodity prices to power AI price recommendations.',
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(c.surfaceAlt),
                                dataRowColor: WidgetStateProperty.all(Colors.transparent),
                                columnSpacing: 32,
                                horizontalMargin: 12,
                                headingTextStyle: TextStyle(
                                    color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                                dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 13),
                                columns: const [
                                  DataColumn(label: Text('Commodity')),
                                  DataColumn(label: Text('Live Market Average')),
                                  DataColumn(label: Text('Baseline Price')),
                                  DataColumn(label: Text('Last Updated')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: priceDocs.map((doc) {
                                  final data = doc.data();
                                  final name = (data['name'] ?? doc.id).toString();
                                  final baseline = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
                                  final liveAverage = computeLiveAverage(products, name);

                                  return DataRow(cells: [
                                    DataCell(Text(name)),
                                    DataCell(Text(
                                      liveAverage != null ? formatPeso(liveAverage) : 'No listings yet',
                                      style: TextStyle(color: c.textSecondary),
                                    )),
                                    DataCell(Text(formatPeso(baseline),
                                        style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(Text(timeAgo(data['updatedAt'] as Timestamp?))),
                                    DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Update baseline',
                                          icon: Icon(Icons.edit_outlined, size: 18, color: c.textSecondary),
                                          onPressed: () => _openBaselineDialog(
                                            context,
                                            commodityId: doc.id,
                                            name: name,
                                            price: baseline,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Remove baseline',
                                          icon: Icon(Icons.delete_outline, size: 18, color: c.red),
                                          onPressed: () => _deleteBaseline(context, doc.id, name),
                                        ),
                                      ],
                                    )),
                                  ]);
                                }).toList(),
                              ),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BaselinePriceDialog extends StatefulWidget {
  final String? commodityId;
  final String? initialName;
  final double? initialPrice;

  const _BaselinePriceDialog({this.commodityId, this.initialName, this.initialPrice});

  @override
  State<_BaselinePriceDialog> createState() => _BaselinePriceDialogState();
}

class _BaselinePriceDialogState extends State<_BaselinePriceDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName ?? '');
  late final TextEditingController _priceController =
      TextEditingController(text: widget.initialPrice != null ? widget.initialPrice!.toStringAsFixed(2) : '');

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _products = [];
  bool _loadingProducts = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('products').get();
      if (mounted) setState(() { _products = snap.docs; _loadingProducts = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a commodity name.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    if (!await ConnectivityService.instance.checkNow()) {
      if (mounted) setState(() { _saving = false; _error = kNoInternetActionMessage; });
      return;
    }

    try {
      final docId = widget.commodityId ??
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final docRef = FirebaseFirestore.instance.collection('market_prices').doc(docId);
      final existing = await docRef.get();

      await docRef.set({
        'name': name,
        'baselinePrice': price,
        'previousBaselinePrice': existing.data()?['baselinePrice'],
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'admin',
      }, SetOptions(merge: true));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveAverage = _loadingProducts
        ? null
        : computeLiveAverage(_products, _nameController.text);

    return AlertDialog(
      title: Text(widget.commodityId == null ? 'Set Baseline Price' : 'Update Baseline Price'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              enabled: widget.commodityId == null,
              decoration: const InputDecoration(labelText: 'Commodity name', hintText: 'e.g. Rice'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Baseline price (₱)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            // "Test price calculation": shows what the live listings say,
            // right next to the baseline the admin is about to commit.
            Text(
              _loadingProducts
                  ? 'Checking live listings…'
                  : liveAverage != null
                      ? 'Live market average right now: ${formatPeso(liveAverage)}'
                      : 'No live listings match this name yet.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}