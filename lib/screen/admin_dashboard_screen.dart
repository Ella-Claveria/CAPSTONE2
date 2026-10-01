import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../data/commodity_master_list.dart';
import 'verification_queue_view.dart';
import 'farmer_list_view.dart';
import 'moderation_queue_view.dart';
import '../widgets/agritrade_text.dart';
import '../data/laurel_barangays.dart';
import '../services/connectivity_service.dart';
import '../services/market_price_helpers.dart';
import '../services/farmer_revenue_service.dart';
import '../services/market_trend_service.dart';
import '../widgets/change_password_dialog.dart';
import '../services/pdf_report_service.dart';
import '../services/audit_log_service.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/geocoding_service.dart';
import '../widgets/chart_capture_boundary.dart';
import 'admin_analytics_widgets.dart';
import 'audit_log_view.dart';
import 'export_options_dialog.dart';

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
    bg: Color(0xFF101713),
    sidebarBg: Color(0xFF111B14),
    surface: Color(0xFF18231B),
    surfaceAlt: Color(0xFF202D23),
    border: Color(0xFF2B3B2F),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF9AA1AC),
    textMuted: Color(0xFF5B616C),
    iconInactive: Colors.white70,
    green: Color(0xFF63C174),
    greenBg: Color(0x2963C174),
    red: Color(0xFFF87171),
    redBg: Color(0x29F87171),
    amber: Color(0xFFFBBF24),
    amberBg: Color(0x29FBBF24),
    blue: Color(0xFF60A5FA),
    blueBg: Color(0x2960A5FA),
  );

  static const light = AdminPalette(
    isDark: false,
    bg: Color(0xFFF8F9FA),
    sidebarBg: Colors.white,
    surface: Colors.white,
    surfaceAlt: Color(0xFFF1F3F5),
    border: Color(0xFFE2E5E9),
    textPrimary: Color(0xFF17241A),
    textSecondary: Color(0xFF676D78),
    textMuted: Color(0xFFA0A5AF),
    iconInactive: Color(0xFF52575F),
    green: Color(0xFF24833D),
    greenBg: Color(0x2024833D),
    red: Color(0xFFDC2626),
    redBg: Color(0x20DC2626),
    amber: Color(0xFFD97706),
    amberBg: Color(0x20D97706),
    blue: Color(0xFF2563EB),
    blueBg: Color(0x202563EB),
  );
}

/// Standardized corner radii for the admin area — theme-invariant (same in
/// light/dark), so it's a plain constants holder rather than a field on
/// [AdminPalette]. Replaces the previously scattered 9-20px literals across
/// individual widgets with exactly two values: [card] for content
/// containers (stat cards, chart cards, section panels) and [control] for
/// smaller interactive elements (buttons, badges, nav tiles, inputs).
class AdminRadii {
  AdminRadii._();
  static const double card = 12;
  static const double control = 8;
}

/// Provides the current [AdminPalette] + a theme-toggle callback to the
/// whole admin subtree, so any descendant widget can read
/// `AdminThemeScope.of(context).palette` without prop-drilling.
class AdminThemeScope extends InheritedWidget {
  final AdminPalette palette;
  final VoidCallback onToggleTheme;

  const AdminThemeScope({
    super.key,
    required this.palette,
    required this.onToggleTheme,
    required super.child,
  });

  bool get isDark => palette.isDark;

  static AdminThemeScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminThemeScope>();
    assert(scope != null, 'AdminThemeScope not found above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AdminThemeScope oldWidget) =>
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
  _NavItem(Icons.groups_outlined, Icons.groups_rounded, 'Farmer List'),
  _NavItem(Icons.gavel_outlined, Icons.gavel_rounded, 'Moderation Queue'),
  _NavItem(Icons.price_change_outlined, Icons.price_change_rounded, 'Price Management'),
  _NavItem(Icons.fact_check_outlined, Icons.fact_check_rounded, 'Audit Log'),
];

// Index (into _navItems/_pages) of the first item in the "System" group —
// rendered with a small section label above it when the sidebar is
// expanded. Everything before this index is ungrouped.
const int _systemGroupStart = 6;

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
  bool _railExpanded = true;
  bool _isDark = false; // Match the AgriTrade+ light admin reference by default.

  // TODO: persist this choice (e.g. SharedPreferences) so it survives app
  // restarts, and/or seed it from the platform brightness on first launch.
  void _toggleTheme() => setState(() => _isDark = !_isDark);

  void _goTo(int index) => setState(() => _selectedIndex = index);
  void _toggleRail() => setState(() => _railExpanded = !_railExpanded);

  Future<void> _logout() async {
    try {
      // Must log while still signed in — the Cloud Function needs an
      // authenticated caller to attribute this entry to the right admin.
      await AuditLogService.log(AuditAction.logout, 'Logged out of the Admin Portal.');
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
    const _AnalyticsDashboardView(),
    const _DemandHeatmapView(),
    const VerificationQueueView(),
    const FarmerListView(),
    const ModerationQueueView(),
    const _PriceManagementView(),
    const AuditLogView(),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _isDark ? AdminPalette.dark : AdminPalette.light;

    return AdminThemeScope(
      palette: palette,
      onToggleTheme: _toggleTheme,
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: palette.isDark ? Brightness.dark : Brightness.light,
            primary: palette.green,
            surface: palette.surface,
            onSurface: palette.textPrimary,
          ),
          scaffoldBackgroundColor: palette.bg,
          cardTheme: CardThemeData(
            color: palette.surface,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: palette.border),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: palette.surfaceAlt,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.green, width: 1.5)),
          ),
        ),
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
                  const _AdminTopHeader(),
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
      )),
    );
  }
}

// ============================================================
// TOP HEADER — notification bell only. Search moved into the sidebar's
// own page-search field; theme toggle and account/logout moved to the
// sidebar footer (see _AdminSidebar) so the header stays minimal.
// ============================================================
class _AdminTopHeader extends StatelessWidget {
  const _AdminTopHeader();

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: const Row(
        children: [
          Spacer(),
          _NotificationBell(),
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
    final scope = AdminThemeScope.of(context);
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
    final c = AdminThemeScope.of(context).palette;
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
// SIDEBAR — collapsible AgriTrade panel with branded navigation,
// quick page search, and an AgriTrade photo panel at the bottom.
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

  static const double _collapsedWidth = 76;
  static const double _expandedWidth = 258;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    // Docked, not floating: no margin/rounding/shadow — flush against the
    // window edge, same flat-panel language as the rest of the redesign.
    // The 1px divider between sidebar and content (drawn by the parent Row)
    // is what separates it visually, not a card border.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: expanded ? _expandedWidth : _collapsedWidth,
      color: c.sidebarBg,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 8, vertical: 12),
          child: Column(
            children: [
              _SidebarBrandToggle(expanded: expanded, onToggle: onToggleExpand),
              if (expanded) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: TextField(
                    textInputAction: TextInputAction.search,
                    onSubmitted: (query) {
                      final normalized = query.trim().toLowerCase();
                      if (normalized.isEmpty) return;
                      final index = _navItems.indexWhere(
                        (item) => item.label.toLowerCase().contains(normalized),
                      );
                      if (index >= 0) onDestinationSelected(index);
                    },
                    style: TextStyle(color: c.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search pages...',
                      hintStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.textSecondary),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      filled: true,
                      fillColor: c.surfaceAlt,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.green, width: 1.2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ] else
                const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _navItems.length,
                  itemBuilder: (context, index) {
                    final item = _navItems[index];
                    final selected = index == selectedIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index == _systemGroupStart)
                            _SidebarSectionLabel(expanded: expanded, label: 'System'),
                          _SidebarNavTile(
                            icon: selected ? item.selectedIcon : item.icon,
                            label: item.label,
                            selected: selected,
                            expanded: expanded,
                            onTap: () => onDestinationSelected(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 8),
              if (expanded)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _ThemeToggleButton(),
                    _AdminAccountMenu(onLogout: onLogout),
                  ],
                )
              else
                Column(
                  children: [
                    const _ThemeToggleButton(),
                    const SizedBox(height: 8),
                    _AdminAccountMenu(onLogout: onLogout),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar's brand mark and expand/collapse control combined into one
/// hoverable area, instead of a logo+wordmark row plus a separate chevron
/// button — expanded shows just the "AgriTrade+" wordmark, collapsed shows
/// just the logo; hovering either swaps it for a chevron so the control
/// still visibly invites a click.
class _SidebarBrandToggle extends StatefulWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _SidebarBrandToggle({required this.expanded, required this.onToggle});

  @override
  State<_SidebarBrandToggle> createState() => _SidebarBrandToggleState();
}

class _SidebarBrandToggleState extends State<_SidebarBrandToggle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    Widget logo(double size) => Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(Icons.agriculture_rounded, color: c.green, size: size - 4),
        );

    final Widget content;
    if (widget.expanded) {
      content = _hovering
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Opacity(opacity: 0.5, child: AgriTradeText(fontSize: 19, light: c.isDark)),
                Icon(Icons.chevron_left_rounded, color: c.textSecondary),
              ],
            )
          : Align(alignment: Alignment.centerLeft, child: AgriTradeText(fontSize: 19, light: c.isDark));
    } else {
      content = Center(
        child: _hovering ? Icon(Icons.chevron_right_rounded, color: c.textSecondary, size: 28) : logo(34),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: SizedBox(
          height: 40,
          child: Tooltip(
            message: widget.expanded ? 'Collapse sidebar' : 'Expand sidebar',
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Small "SYSTEM" caption above the Audit Log entry — collapsed to a thin
/// divider when the rail is icon-only, since there's no room for a label.
class _SidebarSectionLabel extends StatelessWidget {
  final bool expanded;
  final String label;
  const _SidebarSectionLabel({required this.expanded, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Divider(color: c.border, height: 1),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.montserrat(
          color: c.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
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

  // Compact rows; the selected item gets a subtle tinted background plus a
  // left accent bar — never a full color fill — matching the rest of the
  // redesign's "borders/accents, not blocks of color" language.
  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final iconColor = selected ? c.green : c.textSecondary;

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminRadii.control),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 11 : 0),
          decoration: BoxDecoration(
            color: selected ? c.greenBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AdminRadii.control),
            border: Border(left: BorderSide(color: selected ? c.green : Colors.transparent, width: 3)),
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
                        style: GoogleFonts.montserrat(
                          color: selected ? c.green : c.textPrimary,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _AdminAccountMenu extends StatelessWidget {
  final VoidCallback onLogout;
  const _AdminAccountMenu({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final scope = AdminThemeScope.of(context);
    final c = scope.palette;

    // TODO: replace initials/name with the authenticated admin's real profile
    // data (e.g. FirebaseAuth.instance.currentUser / a Firestore admins doc).
    const initials = 'AD';

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
      offset: const Offset(0, 44),
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
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceAlt),
        child: avatar,
      ),
    );
  }
}

// ============================================================
// SMALL REUSABLE PIECES (cards, badges, buttons)
// ============================================================

class AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final IconData icon;
  final Color Function(AdminPalette c) iconColor;
  final Color Function(AdminPalette c) iconBg;
  final bool isEmpty;

  const AdminStatCard({
    super.key,
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
    final c = AdminThemeScope.of(context).palette;
    // No pastel icon box — a flat monochrome icon plus a thin left accent
    // border carries each KPI's color identity instead, matching the
    // redesign's "subtle borders over color blocks" direction.
    final accent = isEmpty ? c.textMuted : iconColor(c);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border(
          top: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isEmpty ? c.textMuted : c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(delta,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isEmpty ? c.textMuted : c.green, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class AdminStatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;

  const AdminStatusBadge({super.key, required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AdminRadii.control)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class AdminQuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  const AdminQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: c.green,
          foregroundColor: c.isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadii.control)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminRadii.control)),
      ),
    );
  }
}

/// Generic empty-state block reused across dashboard sections.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AdminEmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: c.greenBg, borderRadius: BorderRadius.circular(AdminRadii.card)),
              child: Icon(icon, size: 29, color: c.green),
            ),
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
class AdminLoadingSpinner extends StatelessWidget {
  const AdminLoadingSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AdminRadii.card), border: Border.all(color: c.border)),
          child: CircularProgressIndicator(color: c.green),
        ),
      ),
    );
  }
}

/// Shown when a dashboard stream errors out (e.g. permission denied,
/// offline with nothing cached) instead of silently rendering empty data.
class AdminStreamError extends StatelessWidget {
  static const String message = 'Could not load this data. Check your connection and try again.';
  final String? source;
  final Object? error;

  const AdminStreamError({super.key, this.source, this.error});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: c.red, size: 32),
            const SizedBox(height: 10),
            Text(
              source == null ? message : 'Could not load $source. Check your connection and admin access.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (error != null && kDebugMode) ...[
              const SizedBox(height: 6),
              SelectableText(
                error.toString(),
                style: TextStyle(color: c.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section's title + optional subtitle — the visual-hierarchy primitive
/// the Analytics Dashboard uses to separate Overview / Sales Performance /
/// Transaction Breakdown / Market Intelligence from each other, instead of
/// relying on spacing alone.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
        ],
      ],
    );
  }
}

// ============================================================
// ANALYTICS DASHBOARD (main admin landing view)
// Wired to live Firestore collections: users, verificationDocs,
// reports, orders, and market_prices.
// ============================================================

class _AnalyticsDashboardView extends StatelessWidget {
  const _AnalyticsDashboardView();

  Future<void> _openExportDialog(BuildContext context) {
    // showDialog's builder context sits in the root Overlay, outside this
    // screen's own AdminThemeScope subtree — capture the palette from the
    // calling context (which does have it) and pass it down explicitly,
    // same fix already used for the Demand Heatmap's fullscreen route.
    final palette = AdminThemeScope.of(context).palette;
    return showDialog<void>(
      context: context,
      builder: (_) => ExportOptionsDialog(palette: palette),
    );
  }

  @override
  Widget build(BuildContext context) {
    DashboardDataService.instance.ensureLoaded();
    final c = AdminThemeScope.of(context).palette;
    return _buildBody(context, c);
  }

  Widget _buildBody(BuildContext context, AdminPalette c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- HEADER ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analytics Dashboard',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      'Real-time insights for a stronger and more connected agricultural trade community.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  AdminQuickActionButton(
                    icon: Icons.refresh,
                    label: 'Refresh',
                    onPressed: () async {
                      await DashboardDataService.instance.refresh();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Analytics data refreshed.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  AdminQuickActionButton(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'Export Report',
                    onPressed: () => _openExportDialog(context),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Everything below is fed by DashboardDataService's cached
          // orders/products/market_prices fetch (see dashboard_data_service.
          // dart) — a one-shot .get(), not a live listener, refreshed only
          // on TTL expiry or the Refresh button above. This is deliberate:
          // Total Transaction Value and Transaction Breakdown must always
          // read the exact same orders snapshot or the two could show
          // figures that don't reconcile; Sales Performance and Market
          // Intelligence don't need millisecond freshness either. Only the
          // Overview section's Pending Verifications / Flagged Reports stay
          // on real live streams, scoped narrowly below.
          ListenableBuilder(
            listenable: DashboardDataService.instance,
            builder: (context, _) {
              final svc = DashboardDataService.instance;
              if (!svc.hasLoadedOnce) {
                return svc.lastError != null ? const AdminStreamError() : const AdminLoadingSpinner();
              }

              final orders = svc.orders;
              final products = svc.products;
              final now = DateTime.now();
              final totalTransactionValue = DashboardAnalyticsService.platformTransactionTotal(orders);
              final categoryRevenue = DashboardAnalyticsService.categoryRevenue(orders, products);
              final topProducts = DashboardAnalyticsService.topSellingProducts(orders);
              final baselineByCommodity = <String, double>{
                for (final doc in svc.marketPrices)
                  (doc.data()['name'] ?? doc.id).toString():
                      ((doc.data()['baselinePrice'] as num?)?.toDouble() ?? 0),
              };
              final weeklyPricesByCommodity = <String, List<double?>>{
                for (final name in baselineByCommodity.keys)
                  name: DashboardAnalyticsService.weeklyAveragePrice(orders, name, now: now),
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- 1. OVERVIEW KPIs ----
                  const _SectionHeader(title: 'Overview'),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: DashboardDataService.instance.usersStream,
                    builder: (context, usersSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: DashboardDataService.instance.pendingReportsStream,
                        builder: (context, reportsSnap) {
                          if (usersSnap.hasError || reportsSnap.hasError) {
                            return const AdminStreamError();
                          }
                          if (!usersSnap.hasData || !reportsSnap.hasData) {
                            return const AdminLoadingSpinner();
                          }
                          // Marketplace users only — Admin accounts aren't part of
                          // the Farmer/Buyer user base this KPI reports on. Farmers
                          // only count once an admin has approved them (same field
                          // Verify Farmers writes to) — a pending or rejected
                          // application isn't a real, active marketplace user yet.
                          final userDocs = usersSnap.data!.docs;
                          final farmerCount = DashboardAnalyticsService.farmerCount(userDocs);
                          final buyerCount = DashboardAnalyticsService.buyerCount(userDocs);
                          final pendingVerifications =
                              DashboardAnalyticsService.pendingVerifications(userDocs);
                          final flaggedReports = reportsSnap.data!.docs.length;

                          return _overviewKpiGrid(
                            totalUsers: farmerCount + buyerCount,
                            farmerCount: farmerCount,
                            buyerCount: buyerCount,
                            pendingVerifications: pendingVerifications,
                            flaggedReports: flaggedReports,
                            totalTransactionValue: totalTransactionValue,
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // ---- 2. SALES PERFORMANCE ----
                  const _SectionHeader(title: 'Sales Performance'),
                  const SizedBox(height: 12),
                  _responsiveRow([
                    ChartCaptureBoundary(
                      captureKey: DashboardChartKeys.salesOverview,
                      child: _AdminSalesChartCard(orders: orders.map((d) => d.data()).toList()),
                    ),
                    ChartCaptureBoundary(
                      captureKey: DashboardChartKeys.salesByCategory,
                      child: AdminSalesByCategoryCard(categoryRevenue: categoryRevenue),
                    ),
                  ], flexes: const [3, 2]),

                  const SizedBox(height: 28),

                  // ---- 3. TRANSACTION BREAKDOWN ----
                  const _SectionHeader(title: 'Transaction Breakdown'),
                  const SizedBox(height: 12),
                  _pricingTypeBreakdown(orders, c),

                  const SizedBox(height: 28),

                  // ---- 4. MARKET INTELLIGENCE ----
                  const _SectionHeader(title: 'Market Intelligence'),
                  const SizedBox(height: 12),
                  _responsiveRow([
                    ChartCaptureBoundary(
                      captureKey: DashboardChartKeys.priceTrend,
                      child: AdminPriceTrendCard(
                        baselineByCommodity: baselineByCommodity,
                        weeklyPricesByCommodity: weeklyPricesByCommodity,
                      ),
                    ),
                    AdminTopProductsCard(products: topProducts),
                  ], flexes: const [3, 2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _overviewKpiGrid({
    required int totalUsers,
    required int farmerCount,
    required int buyerCount,
    required int pendingVerifications,
    required int flaggedReports,
    required num totalTransactionValue,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 900 ? 4 : (width >= 560 ? 2 : 1);
      const spacing = 16.0;
      final cardWidth = (width - spacing * (columns - 1)) / columns;
      final cards = [
        AdminStatCard(
          label: 'Total Users',
          value: '$totalUsers',
          delta: '$farmerCount farmers · $buyerCount buyers',
          icon: Icons.groups_2_outlined,
          iconColor: (c) => c.blue,
          iconBg: (c) => c.blueBg,
          isEmpty: totalUsers == 0,
        ),
        AdminStatCard(
          label: 'Pending Verifications',
          value: '$pendingVerifications',
          delta: 'Awaiting admin review',
          icon: Icons.fact_check_outlined,
          iconColor: (c) => c.amber,
          iconBg: (c) => c.amberBg,
          isEmpty: pendingVerifications == 0,
        ),
        AdminStatCard(
          label: 'Flagged Reports',
          value: '$flaggedReports',
          delta: 'Unresolved',
          icon: Icons.flag_outlined,
          iconColor: (c) => c.red,
          iconBg: (c) => c.redBg,
          isEmpty: flaggedReports == 0,
        ),
        AdminStatCard(
          label: 'Total Transaction Value',
          value: formatPeso(totalTransactionValue),
          delta: 'From completed orders',
          icon: Icons.receipt_long_outlined,
          iconColor: (c) => c.green,
          iconBg: (c) => c.greenBg,
          isEmpty: totalTransactionValue == 0,
        ),
      ];
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final card in cards) SizedBox(width: cardWidth, child: card),
        ],
      );
    });
  }
  }

  // Transaction Breakdown section — Retail/Wholesale orders + revenue, all-
  // time (same scope as the Total Transaction Value KPI card). 4 compact
  // tiles matching the other sections' visual weight. See
  // DashboardAnalyticsService.pricingTypeSummary's doc comment for the math.
  Widget _pricingTypeBreakdown(List<QueryDocumentSnapshot<Map<String, dynamic>>> orders, AdminPalette c) {
    final summary = DashboardAnalyticsService.pricingTypeSummary(orders);
    Widget tile(String label, String value, Color accent) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AdminRadii.card),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(width: 3, height: 32, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _responsiveRow([
      tile('Retail Orders', '${summary.retailOrders}', c.blue),
      tile('Retail Revenue', formatPeso(summary.retailRevenue), c.blue),
      tile('Wholesale Orders', '${summary.wholesaleOrders}', c.green),
      tile('Wholesale Revenue', formatPeso(summary.wholesaleRevenue), c.green),
    ]);
  }


// Lays [children] out as a Row of Expanded(flex: flexes[i]) above ~900px,
// or stacks them into a single Column below it — the same breakpoint the
// KPI row already uses.
Widget _responsiveRow(List<Widget> children, {List<int>? flexes}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 900;
      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const SizedBox(height: 16),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(flex: flexes != null ? flexes[i] : 1, child: children[i]),
            if (i != children.length - 1) const SizedBox(width: 16),
          ],
        ],
      );
    },
  );
}

// ---- Platform-wide live sales chart ----
// Reuses FarmerRevenueService.revenueBars, which only ever buckets whatever
// order list it's handed by date — it has no notion of "whose" orders they
// are, so passing it every order on the platform (instead of one farmer's)
// gives an honest, live, platform-wide chart for free.
class _AdminSalesChartCard extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  const _AdminSalesChartCard({required this.orders});

  @override
  State<_AdminSalesChartCard> createState() => _AdminSalesChartCardState();
}

class _AdminSalesChartCardState extends State<_AdminSalesChartCard> {
  FarmerRevenueView _view = FarmerRevenueView.weekly;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final now = DateTime.now();

    final bars = FarmerRevenueService.revenueBars(
      orders: widget.orders,
      view: _view,
      now: now,
    );
    final maxValue = bars.isEmpty
        ? 1.0
        : bars.map((bar) => (bar['value'] as num).toDouble()).reduce((a, b) => a > b ? a : b);
    final totalRevenue = FarmerRevenueService.totalRevenueForRange(
      orders: widget.orders,
      view: _view,
      now: now,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
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
                  Text('Sales Overview',
                      style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Platform-wide, from completed orders',
                      style: TextStyle(color: c.textSecondary, fontSize: 13)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(AdminRadii.control)),
                child: Row(
                  children: [
                    _viewToggleChip(c, 'Week', FarmerRevenueView.weekly),
                    _viewToggleChip(c, 'Month', FarmerRevenueView.monthly),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_view == FarmerRevenueView.weekly ? 'This week' : 'Last 6 months',
              style: TextStyle(fontSize: 12, color: c.textSecondary)),
          Text(formatPeso(totalRevenue),
              style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (totalRevenue == 0)
            const AdminEmptyState(
              icon: Icons.show_chart,
              title: 'No completed sales in this period yet',
              subtitle: 'The chart will fill in as orders complete.',
            )
          else
            SizedBox(
              height: 108,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(bars.length, (i) {
                  final value = (bars[i]['value'] as num).toDouble();
                  final height = maxValue <= 0 ? 0.0 : ((value / maxValue) * 80.0).clamp(8.0, 80.0);
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: height,
                        decoration: BoxDecoration(
                          color: value > 0 ? c.green : c.surfaceAlt,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(bars[i]['label'].toString(),
                          style: TextStyle(fontSize: 10, color: c.textSecondary)),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewToggleChip(AdminPalette c, String label, FarmerRevenueView value) {
    final selected = _view == value;
    return GestureDetector(
      onTap: () => setState(() => _view = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.green : Colors.transparent,
          borderRadius: BorderRadius.circular(AdminRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DEMAND HEATMAP — a smooth, blended density layer (ride-hailing-app
// style) instead of separate per-barangay circles.
//
// Every point is one completed order, plotted at its BUYER's own saved
// location (the pin they set at registration — see
// DashboardAnalyticsService._resolveBuyerArea), filtered to the currently
// selected Month/Year. Buyers naturally cluster by proximity, so several
// nearby (or repeat) buyers blend into visibly stronger heat with no
// separate weighting scheme needed — see _buildDemandPoints below.
// ============================================================

// Muted/light Google Maps style: strips POI business/attraction/worship
// icons and transit/road glyphs so the heat colors stand out, while
// keeping road geometry and place labels for orientation (so street
// names stay readable under the heat layer).
const String _mutedMapStyle = '''
[
  {"featureType": "poi", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.attraction", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.place_of_worship", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.government", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "road", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "landscape", "elementType": "geometry", "stylers": [{"color": "#f7f7f4"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#e8f0e3"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#c9e3f0"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#e2e6dc"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#d8ddd0"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#cfd6c4"}]},
  {"featureType": "administrative", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]}
]
''';

// Color ramp for the custom heat overlay below: yellow (low) -> orange
// (mid) -> red (high). Google deprecated google.maps.visualization
// .HeatmapLayer as of Maps JavaScript API v3.65 (confirmed live, in this
// project, on 2026-09-28 — the map tile itself rendered Google's own
// deprecation error banner) — google_maps_flutter's Heatmap widget still
// only targets that removed API on web, so it's unusable here now. This
// hand-painted overlay (see _DemandHeatmapPainter) replaces it and isn't
// tied to that deprecated library at all.
const Color _heatLow = Color(0xFFFFEB3B); // yellow
const Color _heatMid = Color(0xFFFF9800); // orange
const Color _heatHigh = Color(0xFFE53935); // red = highest demand

Color _heatColorForIntensity(double t) {
  final clamped = t.clamp(0.0, 1.0);
  return clamped <= 0.5
      ? Color.lerp(_heatLow, _heatMid, clamped / 0.5)!
      : Color.lerp(_heatMid, _heatHigh, (clamped - 0.5) / 0.5)!;
}

// Real completed-order demand only — no mock/baseline padding. Every
// point is one completed order at its buyer's real resolved location
// (DashboardAnalyticsService.buyerDemandPoints) — a buyer with no
// location on file at all contributes no point, rather than a fabricated
// one. Several distinct buyers naturally land at different real
// coordinates, so unlike the old barangay-ring version this needs no
// synthetic jitter to avoid a single stacked dot — repeat orders from the
// very same buyer pin legitimately do stack, which is exactly the
// intensity signal a heatmap should show.
List<WeightedLatLng> _buildDemandPoints(List<({double lat, double lng})> buyerPoints) {
  return buyerPoints
      .map((p) => WeightedLatLng(LatLng(p.lat, p.lng), weight: 1))
      .toList();
}

// Pan/zoom-out limit for the heatmap — restricted to Laurel itself
// (computed from the same barangay coordinates the heat points use, plus
// a margin) so panning or zooming out can't drift into neighboring towns
// across the lake (Tagaytay, Talisay, etc).
LatLngBounds _computeLaurelBounds() {
  var minLat = kLaurelBarangayLocations.first.lat;
  var maxLat = minLat;
  var minLng = kLaurelBarangayLocations.first.lng;
  var maxLng = minLng;
  for (final loc in kLaurelBarangayLocations) {
    if (loc.lat < minLat) minLat = loc.lat;
    if (loc.lat > maxLat) maxLat = loc.lat;
    if (loc.lng < minLng) minLng = loc.lng;
    if (loc.lng > maxLng) maxLng = loc.lng;
  }
  const pad = 0.015; // ~1.6km margin so edge barangays aren't flush against the pan limit
  return LatLngBounds(
    southwest: LatLng(minLat - pad, minLng - pad),
    northeast: LatLng(maxLat + pad, maxLng + pad),
  );
}

final LatLngBounds _laurelMapBounds = _computeLaurelBounds();

// Buyers aren't restricted to Laurel (unlike farmers — see
// register_screen.dart), so a buyer-location-based heatmap can have real
// points outside _laurelMapBounds. This expands the pannable area to
// include them (union, not replace) so an admin can actually pan to an
// out-of-town buyer instead of it being permanently unreachable — while
// the common case (every buyer still near Laurel) keeps exactly today's
// behavior, since the union with zero outside points is just
// _laurelMapBounds itself.
LatLngBounds _computeMapBounds(List<({double lat, double lng})> buyerPoints) {
  var minLat = _laurelMapBounds.southwest.latitude;
  var maxLat = _laurelMapBounds.northeast.latitude;
  var minLng = _laurelMapBounds.southwest.longitude;
  var maxLng = _laurelMapBounds.northeast.longitude;
  for (final p in buyerPoints) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  const pad = 0.05;
  return LatLngBounds(
    southwest: LatLng(minLat - pad, minLng - pad),
    northeast: LatLng(maxLat + pad, maxLng + pad),
  );
}

// Three quick-jump zoom presets, shown as buttons alongside full free-form
// zoom (mouse wheel / pinch / double-click, all enabled on the map itself
// — see _HeatmapMap's zoomGesturesEnabled) — a convenience shortcut to a
// curated level, not the only way to zoom.
const double _zoomTownLevel = 12.0;
const double _zoomBarangayLevel = 14.0;
const double _zoomStreetLevel = 16.0;

class _DemandHeatmapView extends StatefulWidget {
  const _DemandHeatmapView();

  @override
  State<_DemandHeatmapView> createState() => _DemandHeatmapViewState();
}

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class _DemandHeatmapViewState extends State<_DemandHeatmapView> {
  static const _center = LatLng(kLaurelCenterLat, kLaurelCenterLng);

  // _usersStream reuses DashboardDataService's shared, app-session-lifetime
  // Stream instance (see dashboard_data_service.dart) instead of opening a
  // second independent 'users' listener — the Analytics Dashboard already
  // subscribes to the same instance. Completed orders / products no longer
  // need their own stream fields at all: DashboardDataService.instance.
  // orders/.products is a cached one-shot fetch shared across every admin
  // page, read directly in build() below via a ListenableBuilder. _geoStream
  // and _searchEventsStream stay page-local — they're unique to this view.
  Stream<QuerySnapshot<Map<String, dynamic>>> get _usersStream => DashboardDataService.instance.usersStream;
  late final _geoStream = FirebaseFirestore.instance.collectionGroup('private').snapshots();
  late final _searchEventsStream = FirebaseFirestore.instance.collection('searchEvents').snapshots();

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
  }

  // Defaults to the current month/year on first open — everything below
  // (the map, Highest Demand Areas, Top Buyer Searches) refreshes together
  // whenever either changes (see build()'s use of these two).
  final DateTime _now = DateTime.now();
  late int _selectedYear = _now.year;
  late int _selectedMonth = _now.month;

  // Survives the fullscreen toggle: fed as initialCameraPosition to
  // whichever _HeatmapMap is on screen, and kept up to date by both the
  // inline and fullscreen instances via the same _onCameraIdle callback
  // — so reopening the inline map after exiting full screen resumes
  // from wherever the admin left off instead of resetting to Laurel's
  // center. (Each _HeatmapMap still creates its own GoogleMapController;
  // this is what makes the *camera position* itself carry over.)
  CameraPosition _camera = const CameraPosition(target: _center, zoom: 12.5);

  // Which month/year the camera was last auto-framed for — null on first
  // build so even the very first render frames on real data if there is
  // any, not just Laurel's fixed center. Deliberately NOT reset by every
  // Firestore snapshot update (only by an actual Month/Year change, below
  // in build()) so the admin's own manual panning within one selection is
  // never yanked back.
  int? _framedMonth;
  int? _framedYear;

  void _onCameraIdle(CameraPosition position) {
    _camera = position;
  }

  static LatLng _centerOf(List<({double lat, double lng})> points) {
    if (points.isEmpty) return _center;
    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  Future<void> _openFullscreen(
    BuildContext context, {
    required List<WeightedLatLng> points,
    required LatLngBounds bounds,
    required VoidCallback onExport,
  }) async {
    final themeScope = AdminThemeScope.of(context);
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, animation, secondaryAnimation) {
          // AdminThemeScope only wraps AdminDashboardScreen's own Scaffold,
          // so a route pushed on the root navigator sits outside it —
          // re-supply the palette the fullscreen page reads via
          // AdminThemeScope.of(context) instead of losing the theme.
          return AdminThemeScope(
            palette: themeScope.palette,
            onToggleTheme: themeScope.onToggleTheme,
            child: _FullscreenHeatmapPage(
              initialCamera: _camera,
              points: points,
              bounds: bounds,
              onCameraIdle: _onCameraIdle,
              onExport: onExport,
            ),
          );
        },
      ),
    );
    // The fullscreen map may have moved the camera further — reflect that
    // on the inline map next time this rebuilds.
    if (mounted) setState(() {});
  }

  Future<void> _exportReport(
    BuildContext context,
    List<({String area, int orderCount, num revenue, double lat, double lng})> demand,
    List<MapEntry<String, int>> topSearches,
  ) async {
    final periodLabel = '${_monthNames[_selectedMonth - 1]} $_selectedYear';
    final bytes = await PdfReportService.buildDemandReport(
      demand: demand.map((d) => (barangay: d.area, orderCount: d.orderCount, revenue: d.revenue)).toList(),
      topSearches: topSearches,
      periodLabel: periodLabel,
    );
    if (!context.mounted) return;
    await PdfReportService.share(bytes, 'agritrade_demand_report.pdf');
    AuditLogService.log(AuditAction.exportReport, 'Exported the Demand Heatmap report ($periodLabel, PDF).');
  }

  Widget _monthYearSelector(AdminPalette c, List<int> years) {
    InputDecoration pillDecoration() => InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          filled: true,
          fillColor: c.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            initialValue: _selectedMonth,
            decoration: pillDecoration(),
            dropdownColor: c.surface,
            style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            icon: Icon(Icons.expand_more, color: c.textSecondary, size: 18),
            items: List.generate(
              12,
              (i) => DropdownMenuItem(value: i + 1, child: Text(_monthNames[i])),
            ),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedMonth = value);
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: DropdownButtonFormField<int>(
            initialValue: years.contains(_selectedYear) ? _selectedYear : years.first,
            decoration: pillDecoration(),
            dropdownColor: c.surface,
            style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            icon: Icon(Icons.expand_more, color: c.textSecondary, size: 18),
            items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedYear = value);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;

    return ListenableBuilder(
      listenable: DashboardDataService.instance,
      builder: (context, _) {
        final svc = DashboardDataService.instance;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersStream,
          builder: (context, usersSnap) {
            // Exact coordinates live under users/{uid}/private/geo (see
            // firestore.rules), not on the main user doc, so the demand
            // heatmap's admin-only view reads them via this collection-group
            // stream and merges them into usersByUid below — the one place in
            // the app that's allowed to see every buyer's real pin at once.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _geoStream,
              builder: (context, geoSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _searchEventsStream,
                  builder: (context, searchSnap) {
                if (usersSnap.hasError || geoSnap.hasError || searchSnap.hasError || svc.lastError != null) {
                  final failedSource = usersSnap.hasError
                      ? 'user profiles'
                      : geoSnap.hasError
                          ? 'saved locations'
                          : searchSnap.hasError
                              ? 'buyer search activity'
                              : 'completed orders or product listings';
                  final streamError = usersSnap.error ?? geoSnap.error ?? searchSnap.error ?? svc.lastError;
                  debugPrint('Demand Heatmap failed to load $failedSource: $streamError');
                  return AdminStreamError(source: failedSource, error: streamError);
                }
                if (!usersSnap.hasData || !geoSnap.hasData || !searchSnap.hasData || !svc.hasLoadedOnce) {
                  return const AdminLoadingSpinner();
                }

                final usersByUid = <String, Map<String, dynamic>>{
                  for (final doc in usersSnap.data!.docs) doc.id: doc.data(),
                };
                for (final doc in geoSnap.data?.docs ?? const []) {
                  if (doc.id != 'geo') continue;
                  final ownerUid = doc.reference.parent.parent?.id;
                  final user = ownerUid == null ? null : usersByUid[ownerUid];
                  if (user == null) continue;
                  user['latitude'] = doc.data()['latitude'];
                  user['longitude'] = doc.data()['longitude'];
                }

                // Every buyer behind a completed order, outside Laurel,
                // with no saved barangay/municipality/province yet —
                // resolved once in the background and cached on their own
                // doc (see GeocodingService), regardless of which month is
                // currently selected, so switching months never re-fires
                // this for a buyer already resolved.
                for (final doc in svc.orders) {
                  final buyerId = (doc.data()['buyerId'] ?? '').toString();
                  if (buyerId.isEmpty) continue;
                  final buyer = usersByUid[buyerId];
                  if (buyer == null) continue;
                  final lat = (buyer['latitude'] as num?)?.toDouble();
                  final lng = (buyer['longitude'] as num?)?.toDouble();
                  if (lat == null || lng == null || isWithinLaurel(lat, lng)) continue;
                  final alreadyResolved = (buyer['barangay'] ?? '').toString().trim().isNotEmpty ||
                      (buyer['municipality'] ?? '').toString().trim().isNotEmpty ||
                      (buyer['province'] ?? '').toString().trim().isNotEmpty;
                  GeocodingService.resolveAndCacheIfNeeded(
                    uid: buyerId,
                    lat: lat,
                    lng: lng,
                    alreadyResolved: alreadyResolved,
                  );
                }

                final years = DashboardAnalyticsService.yearsWithCompletedOrders(
                  svc.orders,
                  _now,
                );
                final rankedDemand = DashboardAnalyticsService.demandByBuyerAreaForMonth(
                  svc.orders,
                  usersByUid,
                  year: _selectedYear,
                  month: _selectedMonth,
                );
                final buyerPoints = DashboardAnalyticsService.buyerDemandPointsForMonth(
                  svc.orders,
                  usersByUid,
                  year: _selectedYear,
                  month: _selectedMonth,
                );
                // The Month/Year selection just changed (or this is the
                // first build) — snap the camera to where this period's
                // real buyer demand actually is instead of leaving it
                // wherever a previous period's data happened to be (or a
                // fixed Laurel-only default), so a period with demand
                // entirely outside Laurel is visible without the admin
                // having to hunt for it by panning.
                if (_framedMonth != _selectedMonth || _framedYear != _selectedYear) {
                  _camera = CameraPosition(target: _centerOf(buyerPoints), zoom: _zoomTownLevel);
                  _framedMonth = _selectedMonth;
                  _framedYear = _selectedYear;
                }
                final topSearches = DashboardAnalyticsService.topSearchQueriesForMonth(
                  searchSnap.data!.docs,
                  year: _selectedYear,
                  month: _selectedMonth,
                );
                final periodLabel = '${_monthNames[_selectedMonth - 1]} $_selectedYear';
                final activeProducts = svc.products
                    .where((d) => d.data()['isArchived'] != true)
                    .map((d) => d.data())
                    .toList();
                // "As of" reference point for the rolling 6-week trend
                // window: the current moment for the current month/year
                // (so today's own activity still counts), otherwise the
                // last moment of the selected month — so this card
                // actually responds to the Month/Year filter like every
                // other figure on this page, instead of always silently
                // showing "as of today" regardless of what period is
                // selected.
                final isCurrentPeriod = _selectedYear == _now.year && _selectedMonth == _now.month;
                final trendsAsOf = isCurrentPeriod
                    ? _now
                    : DashboardAnalyticsService.monthWindow(_selectedYear, _selectedMonth)
                        .end
                        .subtract(const Duration(milliseconds: 1));
                final trends = MarketTrendService.commodityTrends(
                  completedOrders: svc.orders.map((d) => d.data()).toList(),
                  activeProducts: activeProducts,
                  now: trendsAsOf,
                );

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
                          Row(
                            children: [
                              _monthYearSelector(c, years),
                              const SizedBox(width: 12),
                              AdminQuickActionButton(
                                icon: Icons.download,
                                label: 'Export Report',
                                filled: true,
                                onPressed: () => _exportReport(context, rankedDemand, topSearches),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Heat intensity reflects real completed purchases by BUYER location for $periodLabel — '
                        'never the farmer\'s, product\'s, or seller\'s. Positions use each buyer\'s real map pin '
                        '(set at registration); the ranked list groups them by their actual saved area, in Laurel '
                        'or anywhere else.',
                        style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Builder(
                                builder: (context) {
                                  final points = _buildDemandPoints(buyerPoints);
                                  return _HeatmapMap(
                                    initialCamera: _camera,
                                    points: points,
                                    bounds: _computeMapBounds(buyerPoints),
                                    onCameraIdle: _onCameraIdle,
                                    isFullscreen: false,
                                    onToggleFullscreen: () => _openFullscreen(
                                      context,
                                      points: points,
                                      bounds: _computeMapBounds(buyerPoints),
                                      onExport: () => _exportReport(context, rankedDemand, topSearches),
                                    ),
                                  );
                                },
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
                                      title: 'Highest Demand Areas',
                                      icon: Icons.local_fire_department_outlined,
                                      emptyText: 'No completed buyer purchases for $periodLabel.',
                                      rows: rankedDemand
                                          .where((d) => d.orderCount > 0)
                                          .take(6)
                                          .map((d) =>
                                              '${d.area} — ${d.orderCount} completed order${d.orderCount == 1 ? '' : 's'}')
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: _DemandSidePanel(
                                      title: 'Top Buyer Searches',
                                      icon: Icons.search,
                                      emptyText: 'No search activity logged for $periodLabel.',
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
                      const SizedBox(height: 16),
                      _MarketTrendPredictions(trends: trends),
                    ],
                  ),
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
}

// ============================================================
// The map itself: heatmap layer + muted style + the zoom/fullscreen
// button cluster + legend, all as one Stack. Used both inline (embedded
// in _DemandHeatmapView's normal layout) and inside
// _FullscreenHeatmapPage — each use creates its own GoogleMapController,
// so exact camera continuity across the fullscreen toggle is carried by
// _DemandHeatmapViewState._camera (passed in as initialCamera), not by
// reusing the same platform view.
// ============================================================
class _HeatmapMap extends StatefulWidget {
  final CameraPosition initialCamera;
  final List<WeightedLatLng> points;
  final LatLngBounds bounds;
  final ValueChanged<CameraPosition> onCameraIdle;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  // Only shown (as a button in the top-right cluster) while isFullscreen:
  // the normal inline view already has its own "Export Report" button in
  // the page header, which full screen hides along with the rest of the
  // dashboard chrome.
  final VoidCallback? onExport;

  const _HeatmapMap({
    required this.initialCamera,
    required this.points,
    required this.bounds,
    required this.onCameraIdle,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.onExport,
  });

  @override
  State<_HeatmapMap> createState() => _HeatmapMapState();
}

class _HeatmapMapState extends State<_HeatmapMap> {
  GoogleMapController? _controller;
  late final ValueNotifier<CameraPosition> _liveCamera =
      ValueNotifier<CameraPosition>(widget.initialCamera);

  @override
  void dispose() {
    _liveCamera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.isFullscreen ? BorderRadius.zero : BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: widget.initialCamera,
              style: _mutedMapStyle,
              myLocationButtonEnabled: false,
              // Native on-map zoom controls are replaced by the custom
              // zoom-preset buttons below (which can't be positioned next
              // to the Fullscreen button any other way) — the underlying
              // gestures themselves stay fully enabled below, this only
              // swaps which UI draws the +/- buttons.
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              // Mouse wheel, trackpad pinch/scroll, and double-click zoom
              // are all real, standard map interactions and must work
              // normally — never disabled. _DemandHeatmapPainter's heat
              // discs use a fixed SCREEN-pixel radius specifically so they
              // look correct at any zoom level (see its own doc comment:
              // that's what gives a real heatmap layer its "dissipates as
              // you zoom in" look), so free zoom never looks broken.
              zoomGesturesEnabled: true,
              // Rotate/tilt stay off: _DemandHeatmapPainter's projection
              // assumes a simple north-up, no-tilt camera (see _project) —
              // panning and zooming still update it correctly frame to
              // frame, but a rotated/tilted camera would make the painted
              // heat discs visibly drift off their real map position.
              // Neither gesture was requested; only pan/zoom are.
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              // Keeps the map to wherever the real data actually is —
              // Laurel itself, plus any buyer point outside it (see
              // _computeMapBounds) — instead of a fixed Laurel-only lock,
              // since buyers aren't geo-restricted the way farmers are.
              cameraTargetBounds: CameraTargetBounds(widget.bounds),
              minMaxZoomPreference: const MinMaxZoomPreference(6, _zoomStreetLevel + 1),
              onMapCreated: (controller) => _controller = controller,
              onCameraMove: (pos) => _liveCamera.value = pos,
              onCameraIdle: () => widget.onCameraIdle(_liveCamera.value),
            ),
          ),
          // Custom heat overlay: google.maps.visualization.HeatmapLayer was
          // removed from the Maps JavaScript API (Google deprecated it as
          // of v3.65 — confirmed live against this project's key, which
          // isn't pinned to an older version), so google_maps_flutter's
          // Heatmap widget (which only ever targeted that JS class on web)
          // can't be used here. This paints the same blended yellow ->
          // orange -> red look directly with Canvas instead, projecting
          // each point to screen space with the same Web Mercator math
          // Google Maps itself uses (see _DemandHeatmapPainter). Wrapped
          // in IgnorePointer so drag/scroll/click still reach the map.
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ValueListenableBuilder<CameraPosition>(
                    valueListenable: _liveCamera,
                    builder: (context, camera, _) {
                      return CustomPaint(
                        size: constraints.biggest,
                        painter: _DemandHeatmapPainter(points: widget.points, camera: camera),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                if (widget.isFullscreen && widget.onExport != null) ...[
                  _MapIconButton(icon: Icons.download, tooltip: 'Export Report', onPressed: widget.onExport!),
                  const SizedBox(height: 8),
                ],
                _MapIconButton(
                  icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  tooltip: widget.isFullscreen ? 'Exit full screen' : 'Full screen',
                  onPressed: widget.onToggleFullscreen,
                ),
                const SizedBox(height: 8),
                // Three preset zoom levels instead of free-form +/- — see
                // the comment on _zoomTownLevel for why: it keeps the
                // heat discs' fixed-pixel radius always looking
                // intentional rather than landing on an odd in-between
                // zoom.
                _MapIconButton(
                  icon: Icons.zoom_out_map,
                  tooltip: 'Town view',
                  onPressed: () => _controller?.animateCamera(CameraUpdate.zoomTo(_zoomTownLevel)),
                ),
                const SizedBox(height: 4),
                _MapIconButton(
                  icon: Icons.center_focus_weak,
                  tooltip: 'Barangay view',
                  onPressed: () => _controller?.animateCamera(CameraUpdate.zoomTo(_zoomBarangayLevel)),
                ),
                const SizedBox(height: 4),
                _MapIconButton(
                  icon: Icons.zoom_in_map,
                  tooltip: 'Street view',
                  onPressed: () => _controller?.animateCamera(CameraUpdate.zoomTo(_zoomStreetLevel)),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 12,
            bottom: 12,
            child: _HeatmapLegend(),
          ),
        ],
      ),
    );
  }
}

/// Paints [points] as smooth, additively-blended discs colored along the
/// yellow -> orange -> red ramp, projected into screen space with the
/// same Web Mercator formula Google Maps uses internally (so the heat
/// tracks the map correctly through pans and zooms without needing any
/// platform-channel round trip per point/frame).
class _DemandHeatmapPainter extends CustomPainter {
  final List<WeightedLatLng> points;
  final CameraPosition camera;

  const _DemandHeatmapPainter({required this.points, required this.camera});

  // Fixed *screen-space* pixel radius — geographic coverage shrinks as
  // you zoom in, which is exactly the "dissipating" behavior a real
  // heatmap layer has, without any extra zoom-based scaling logic.
  static const double _radius = 34.0;

  static double _lngToFrac(double lng) => (lng + 180.0) / 360.0;

  static double _latToFrac(double lat) {
    final sinLat = sin(lat * pi / 180.0).clamp(-0.9999, 0.9999).toDouble();
    return 0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * pi);
  }

  Offset _project(LatLng point, Size size) {
    final double scale = 256.0 * pow(2.0, camera.zoom).toDouble();
    final double dx = (_lngToFrac(point.longitude) - _lngToFrac(camera.target.longitude)) * scale;
    final double dy = (_latToFrac(point.latitude) - _latToFrac(camera.target.latitude)) * scale;
    return Offset(size.width / 2 + dx, size.height / 2 + dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxWeight = points.map((p) => p.weight).reduce((a, b) => a > b ? a : b);
    if (maxWeight <= 0) return;

    final visibleBounds = (Offset.zero & size).inflate(_radius);

    // Project once and sort ascending by weight, so the highest-demand
    // (reddest) discs paint LAST, on top of the lower ones. With normal
    // alpha compositing (the default BlendMode.srcOver — NOT additive:
    // an earlier version of this used BlendMode.plus, which sums color
    // channels across every overlapping disc and clips to solid white
    // wherever more than a few points are near each other, wiping out
    // the yellow/orange/red gradient entirely) this makes the hottest
    // point in a cluster visually dominate it, exactly like a real
    // weighted heatmap's hot core, while still letting sparser/lower
    // points around it blend smoothly into softer yellow/orange.
    final projected = points
        .map((p) => (offset: _project(p.point, size), t: (p.weight / maxWeight).clamp(0.0, 1.0)))
        .where((p) => visibleBounds.contains(p.offset))
        .toList()
      ..sort((a, b) => a.t.compareTo(b.t));

    for (final p in projected) {
      final color = _heatColorForIntensity(p.t);
      final peakAlpha = (0.30 + 0.40 * p.t).clamp(0.0, 1.0);
      // A radial gradient (solid, saturated color at the center, tapering
      // smoothly to transparent at the edge) reads as clean/defined —
      // MaskFilter.blur (used previously) softens every pixel into a haze,
      // which is what looked "blurry." This keeps the same smooth,
      // hard-edge-free falloff without that soft-focus look.
      final rect = Rect.fromCircle(center: p.offset, radius: _radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: peakAlpha), color.withValues(alpha: 0.0)],
        ).createShader(rect);
      canvas.drawCircle(p.offset, _radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DemandHeatmapPainter oldDelegate) {
    return oldDelegate.camera != camera || !identical(oldDelegate.points, points);
  }
}

/// Small circular button matching Google Maps' own native control style
/// (always white/black regardless of the admin dashboard's dark/light
/// theme) — it sits on top of the map itself, not the surrounding page.
class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _MapIconButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: Colors.black87),
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// "Low -> High demand" gradient key, pinned to the map's bottom-left
/// corner in both the inline and full-screen views.
class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0x00FFEB3B),
                  Color(0xFFFFEB3B),
                  Color(0xFFFF9800),
                  Color(0xFFE53935),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Low → High demand', style: TextStyle(fontSize: 10.5, color: Colors.black54)),
        ],
      ),
    );
  }
}

/// Fills the entire browser viewport with just the map — the admin
/// sidebar and top bar (which live in AdminDashboardScreen's own
/// Scaffold, underneath this pushed route) are hidden simply by being
/// obscured, not torn down, so nothing about them is reloaded either.
class _FullscreenHeatmapPage extends StatelessWidget {
  final CameraPosition initialCamera;
  final List<WeightedLatLng> points;
  final LatLngBounds bounds;
  final ValueChanged<CameraPosition> onCameraIdle;
  final VoidCallback onExport;

  const _FullscreenHeatmapPage({
    required this.initialCamera,
    required this.points,
    required this.bounds,
    required this.onCameraIdle,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: _HeatmapMap(
                initialCamera: initialCamera,
                points: points,
                bounds: bounds,
                onCameraIdle: onCameraIdle,
                isFullscreen: true,
                onToggleFullscreen: () => Navigator.of(context).pop(),
                onExport: onExport,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'Press Esc or tap the exit-fullscreen icon to return',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketTrendPredictions extends StatelessWidget {
  final List<CommodityTrend> trends;
  const _MarketTrendPredictions({required this.trends});

  static IconData _icon(TrendDirection d) {
    switch (d) {
      case TrendDirection.rising:
        return Icons.trending_up;
      case TrendDirection.falling:
        return Icons.trending_down;
      case TrendDirection.stable:
        return Icons.trending_flat;
    }
  }

  static String _label(TrendDirection d) {
    switch (d) {
      case TrendDirection.rising:
        return 'Rising';
      case TrendDirection.falling:
        return 'Falling';
      case TrendDirection.stable:
        return 'Stable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    Color colorFor(TrendDirection d) =>
        d == TrendDirection.rising ? c.green : (d == TrendDirection.falling ? c.red : c.textSecondary);

    return Container(
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
          Text('Market Trend Predictions',
              style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Price movement and local supply, projected from recent weekly trends — statistical, not a trained model.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          if (trends.isEmpty)
            const AdminEmptyState(
              icon: Icons.show_chart,
              title: 'Not enough data yet',
              subtitle: 'Trends appear once there are a few weeks of listings and completed orders.',
            )
          else
            SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: trends.length,
                itemBuilder: (context, index) {
                  final t = trends[index];
                  return Container(
                    width: 220,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(_icon(t.priceDirection), size: 15, color: colorFor(t.priceDirection)),
                            const SizedBox(width: 4),
                            Text('Price: ${_label(t.priceDirection)}',
                                style: TextStyle(fontSize: 12, color: colorFor(t.priceDirection), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (t.projectedNextPrice != null) ...[
                          const SizedBox(height: 2),
                          Text('~${formatPeso(t.projectedNextPrice!)} next week',
                              style: TextStyle(fontSize: 11, color: c.textSecondary)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(_icon(t.supplyDirection), size: 15, color: colorFor(t.supplyDirection)),
                            const SizedBox(width: 4),
                            Text('Supply: ${_label(t.supplyDirection)}',
                                style: TextStyle(fontSize: 12, color: colorFor(t.supplyDirection), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('~${t.projectedNextWeekListings} new listing(s) next week',
                            style: TextStyle(fontSize: 11, color: c.textSecondary)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
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
    final c = AdminThemeScope.of(context).palette;
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
// "Current Market Average" is computed on the fly from active Farmer
// `products` listings only; "Admin Reference Price" is what the
// admin sets here (manually or via file import) and is meant to
// feed the price-recommendation system.
// ============================================================

// A single cell's value, normalized from either .xlsx (typed CellValue) or
// .csv (plain string) into one shape the row-validation logic below can
// read without caring which format it came from. [nativeDate] is only ever
// set for a genuine Excel date cell (DateCellValue/DateTimeCellValue) — CSV
// and text-formatted date cells fall back to string parsing instead.
class _Cell {
  final String text;
  final DateTime? nativeDate;
  const _Cell(this.text, {this.nativeDate});
  bool get isBlank => text.trim().isEmpty;
}

// excel v4's CellValue is a sealed class with typed subclasses per cell
// kind (text/int/double/date/bool/formula) instead of raw Dart values —
// this extracts the real display text for every one of them in one place.
String _cellPlainText(CellValue? value) {
  return switch (value) {
    null => '',
    TextCellValue v => v.value.toString().trim(),
    IntCellValue v => v.value.toString(),
    DoubleCellValue v => v.value.toString(),
    DateCellValue v => v.asDateTimeLocal().toIso8601String(),
    DateTimeCellValue v => v.asDateTimeLocal().toIso8601String(),
    BoolCellValue v => v.value.toString(),
    FormulaCellValue v => v.formula,
    _ => value.toString(),
  };
}

// Combines a price with its commodity's configured unit (e.g. "kg",
// "piece", "kg liveweight") instead of assuming everything is per
// kilogram — falls back to "kg" only when the record genuinely has no
// unit configured (older records predating the Unit field).
String _formatPriceWithUnit(num price, String? unit) {
  final label = (unit == null || unit.trim().isEmpty) ? 'kg' : unit.trim();
  return '${formatPeso(price)}/$label';
}

DateTime? _cellNativeDate(CellValue? value) {
  if (value is DateCellValue) return value.asDateTimeLocal();
  if (value is DateTimeCellValue) return value.asDateTimeLocal();
  return null;
}

// A tolerant reader, not a full RFC 4180 CSV parser, since commodity names/
// prices/dates never need embedded commas or quoted fields.
List<List<_Cell>> _csvCellRows(String content) {
  final rows = <List<_Cell>>[];
  for (final rawLine in content.split(RegExp(r'\r\n|\r|\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    rows.add(line
        .split(',')
        .map((cell) => _Cell(cell.trim().replaceAll(RegExp(r'^"|"$'), '')))
        .toList());
  }
  return rows;
}

List<List<_Cell>> _xlsxCellRows(Uint8List bytes) {
  final workbook = Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) return [];
  final sheet = workbook.tables[workbook.tables.keys.first]!;
  return sheet.rows.map((row) {
    return row.map((cell) {
      final value = cell?.value;
      return _Cell(_cellPlainText(value), nativeDate: _cellNativeDate(value));
    }).toList();
  }).toList();
}

String _normalizeHeader(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Map<String, int> _headerIndex(List<_Cell> headerRow) {
  final index = <String, int>{};
  for (var i = 0; i < headerRow.length; i++) {
    final norm = _normalizeHeader(headerRow[i].text);
    if (norm.isNotEmpty) index.putIfAbsent(norm, () => i);
  }
  return index;
}

int? _resolveColumn(Map<String, int> normalizedHeaderIndex, List<String> aliases) {
  for (final alias in aliases) {
    final idx = normalizedHeaderIndex[alias];
    if (idx != null) return idx;
  }
  return null;
}

// Accepts ISO/native Excel dates first, then a handful of common
// spreadsheet date formats admins are likely to have typed by hand.
DateTime? _parseDateText(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso;
  for (final pattern in ['M/d/yyyy', 'MM/dd/yyyy', 'yyyy/MM/dd', 'MMM d, yyyy', 'MMMM d, yyyy', 'd MMM yyyy', 'MM-dd-yyyy']) {
    try {
      return DateFormat(pattern).parseStrict(t);
    } catch (_) {}
  }
  return null;
}

// One row from an imported price file, already validated. [error] is null
// exactly when the row is importable; every rejection reason is a plain,
// specific sentence — never just "invalid" — so the preview dialog (and
// the "Show clear errors" requirement) has something real to display.
class _PriceImportRow {
  final int rowNumber;
  final String rawName;
  final String? matchedCommodity;
  final String? category;
  final double? referencePrice;
  final DateTime? effectiveDate;
  final double? minimumPrice;
  final double? maximumPrice;
  final String? unit;
  final String? source;
  final bool isTestData;
  final String? error;

  const _PriceImportRow({
    required this.rowNumber,
    required this.rawName,
    this.matchedCommodity,
    this.category,
    this.referencePrice,
    this.effectiveDate,
    this.minimumPrice,
    this.maximumPrice,
    this.unit,
    this.source,
    this.isTestData = false,
    this.error,
  });

  bool get isValid => error == null;
  String get displayName => matchedCommodity ?? rawName;
}

class _PriceImportParseResult {
  final String? headerError;
  final List<_PriceImportRow> rows;
  const _PriceImportParseResult({this.headerError, this.rows = const []});
}

// The new supported layout: CommodityID, Category, CommodityName, Unit,
// ReferencePrice, MinimumPrice, MaximumPrice, EffectiveDate, Source,
// IsTestData — matched by header name (case/spacing-insensitive), not
// fixed column position, with a couple of legacy aliases ("name", "price")
// so the header-based error below is clear even for an old-format file
// instead of the old blanket "No valid rows found."
_PriceImportParseResult _buildImportRows(List<List<_Cell>> rawRows) {
  if (rawRows.isEmpty) {
    return const _PriceImportParseResult(headerError: 'This file appears to be empty.');
  }

  final index = _headerIndex(rawRows.first);
  final nameCol = _resolveColumn(index, const ['commodityname', 'commodity', 'name', 'productname', 'product']);
  final priceCol = _resolveColumn(index, const ['referenceprice', 'baselineprice', 'price']);
  final dateCol = _resolveColumn(index, const ['effectivedate', 'date']);

  final missing = <String>[];
  if (nameCol == null) missing.add('CommodityName');
  if (priceCol == null) missing.add('ReferencePrice');
  if (dateCol == null) missing.add('EffectiveDate');
  if (missing.isNotEmpty) {
    return _PriceImportParseResult(
      headerError: 'This file is missing required column(s): ${missing.join(', ')}. Expected headers: '
          'CommodityID, Category, CommodityName, Unit, ReferencePrice, MinimumPrice, MaximumPrice, '
          'EffectiveDate, Source, IsTestData (CommodityName, ReferencePrice, and EffectiveDate are required).',
    );
  }

  final unitCol = _resolveColumn(index, const ['unit']);
  final minCol = _resolveColumn(index, const ['minimumprice', 'minprice']);
  final maxCol = _resolveColumn(index, const ['maximumprice', 'maxprice']);
  final sourceCol = _resolveColumn(index, const ['source']);
  final testCol = _resolveColumn(index, const ['istestdata', 'testdata']);

  _Cell cellAt(List<_Cell> cells, int? col) => (col != null && col < cells.length) ? cells[col] : const _Cell('');

  final results = <_PriceImportRow>[];
  final seenCommodities = <String>{};
  var rowNumber = 1;

  for (final cells in rawRows.skip(1)) {
    rowNumber++;
    if (cells.every((c) => c.isBlank)) continue; // blank rows are skipped, not flagged invalid

    final rawName = cellAt(cells, nameCol).text;
    final priceText = cellAt(cells, priceCol).text;
    final dateCell = cellAt(cells, dateCol);
    final unit = cellAt(cells, unitCol).text;
    final source = cellAt(cells, sourceCol).text;
    final testText = cellAt(cells, testCol).text;

    String? error;
    String? matched;
    double? price;
    DateTime? effectiveDate;

    if (rawName.isEmpty) {
      error = 'Missing commodity name';
    } else {
      matched = matchSupportedCommodity(rawName);
      if (matched == null) error = 'Not a supported AgriTrade+ commodity';
    }

    if (error == null) {
      if (priceText.isEmpty) {
        error = 'Missing reference price';
      } else {
        price = double.tryParse(priceText.replaceAll(',', ''));
        if (price == null) {
          error = 'Invalid reference price';
        } else if (price <= 0) {
          error = 'Reference price must be greater than zero';
        }
      }
    }

    if (error == null) {
      if (dateCell.isBlank) {
        error = 'Missing effective date';
      } else {
        effectiveDate = dateCell.nativeDate ?? _parseDateText(dateCell.text);
        if (effectiveDate == null) error = 'Invalid effective date';
      }
    }

    if (error == null && matched != null) {
      final key = matched.toLowerCase();
      if (!seenCommodities.add(key)) {
        error = 'Duplicate commodity in this file — only the first occurrence is imported';
      }
    }

    results.add(_PriceImportRow(
      rowNumber: rowNumber,
      rawName: rawName,
      matchedCommodity: matched,
      category: matched != null ? categoryOfCommodity(matched) : null,
      referencePrice: price,
      effectiveDate: effectiveDate,
      minimumPrice: double.tryParse(cellAt(cells, minCol).text.replaceAll(',', '')),
      maximumPrice: double.tryParse(cellAt(cells, maxCol).text.replaceAll(',', '')),
      unit: unit.isEmpty ? null : unit,
      source: source.isEmpty ? null : source,
      isTestData: const ['true', '1', 'yes'].contains(testText.toLowerCase()),
      error: error,
    ));
  }

  return _PriceImportParseResult(rows: results);
}

class _PriceManagementView extends StatelessWidget {
  const _PriceManagementView();

  Future<void> _openBaselineDialog(
    BuildContext context, {
    String? commodityId,
    String? name,
    double? price,
    String? unit,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BaselinePriceDialog(
        commodityId: commodityId,
        initialName: name,
        initialPrice: price,
        initialUnit: unit,
      ),
    );
    if (saved == true) {
      DashboardDataService.instance.refresh(force: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin reference price saved.')),
        );
      }
    }
  }

  Future<void> _importPricesCsv(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    if (files.isEmpty) return;
    final file = files.first;

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
      }
      return;
    }

    final List<List<_Cell>> rawRows;
    try {
      rawRows = (file.extension ?? '').toLowerCase() == 'xlsx'
          ? _xlsxCellRows(bytes)
          : _csvCellRows(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not read that file — make sure it's a valid .csv or .xlsx file.")),
        );
      }
      return;
    }

    final parsed = _buildImportRows(rawRows);
    if (parsed.headerError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parsed.headerError!)));
      }
      return;
    }
    if (parsed.rows.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rows found in this file — it may only contain a header row.')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    // Preview first — every row (valid and invalid) is shown before
    // anything touches Firestore; the admin explicitly confirms which
    // rows to import (only the valid ones ever get written).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _PriceImportPreviewDialog(rows: parsed.rows, fileName: file.name),
    );
    if (confirmed != true) return;

    final validRows = parsed.rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) return;

    if (!context.mounted) return;
    if (!await ConnectivityService.instance.checkNow()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      }
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final updatedBy = FirebaseAuth.instance.currentUser?.email ??
        FirebaseAuth.instance.currentUser?.uid ??
        'admin';
    final batch = firestore.batch();
    for (final row in validRows) {
      // Keyed by the matched, canonical commodity name — never the file's
      // own CommodityID — so an existing commodity is always updated in
      // place instead of creating a duplicate.
      final commodity = row.matchedCommodity!;
      final docId = commodity.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final docRef = firestore.collection('market_prices').doc(docId);
      final existing = await docRef.get();
      batch.set(docRef, {
        'name': commodity,
        'category': row.category,
        'baselinePrice': row.referencePrice,
        'previousBaselinePrice': existing.data()?['baselinePrice'],
        'effectiveDate': Timestamp.fromDate(row.effectiveDate!),
        if (row.unit != null) 'unit': row.unit,
        if (row.source != null) 'source': row.source,
        'isTestData': row.isTestData,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      }, SetOptions(merge: true));
    }
    await batch.commit();
    DashboardDataService.instance.refresh(force: true);

    final skipped = parsed.rows.length - validRows.length;
    AuditLogService.log(
      AuditAction.importBaselinePrices,
      'Imported ${validRows.length} commodity price(s) from ${file.name}'
      '${skipped > 0 ? ' ($skipped row(s) skipped as invalid)' : ''}.',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${validRows.length} commodity price(s).')),
      );
    }
  }

  Future<void> _deleteBaseline(BuildContext context, String commodityId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove admin reference price?'),
        content: Text('This removes the official admin reference price for "$name". This cannot be undone.'),
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
    DashboardDataService.instance.refresh(force: true);
    AuditLogService.log(AuditAction.deleteBaselinePrice, 'Removed the admin reference price for "$name".');
  }

  @override
  Widget build(BuildContext context) {
    DashboardDataService.instance.ensureLoaded();
    final c = AdminThemeScope.of(context).palette;
    // The whole page (header/buttons + table) scrolls as one unit — the
    // sidebar and top header outside this widget stay fixed. No nested
    // vertical scroll region for the table itself, so the browser's normal
    // scrollbar reaches every row and the action buttons at the bottom.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Commodity Price Management',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.textPrimary)),
              Row(
                children: [
                  AdminQuickActionButton(
                    icon: Icons.refresh,
                    label: 'Refresh All',
                    onPressed: () async {
                      await DashboardDataService.instance.refresh();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Prices and analytics data refreshed.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  AdminQuickActionButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Import File',
                    onPressed: () => _importPricesCsv(context),
                  ),
                  const SizedBox(width: 8),
                  AdminQuickActionButton(
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
          ListenableBuilder(
            listenable: DashboardDataService.instance,
            builder: (context, _) {
              final svc = DashboardDataService.instance;
              if (!svc.hasLoadedOnce) {
                return svc.lastError != null ? const AdminStreamError() : const AdminLoadingSpinner();
              }

              final priceDocs = svc.marketPrices;
              final products = svc.products;

              return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    // Sized to fit its content naturally (no fixed/bounded
                    // height here) — the page-level scroll above is what
                    // reveals rows past the viewport, not a clipped box.
                    child: priceDocs.isEmpty
                        ? const AdminEmptyState(
                            icon: Icons.price_change_outlined,
                            title: 'No admin reference prices set yet',
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
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('Current Market Average (Retail)')),
                                DataColumn(label: Text('Current Market Average (Wholesale)')),
                                DataColumn(label: Text('Admin Reference Price')),
                                DataColumn(label: Text('Unit')),
                                DataColumn(label: Text('Effective Date')),
                                DataColumn(label: Text('Source')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: priceDocs.map((doc) {
                                final data = doc.data();
                                final name = (data['name'] ?? doc.id).toString();
                                final baseline = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
                                // Current Market Average comes ONLY from
                                // active Farmer listings — never the admin's
                                // reference price (see computeLiveAverage).
                                final liveAverage = computeLiveAverage(products, name);
                                final wholesaleLiveAverage = computeWholesaleLiveAverage(products, name);
                                final category = (data['category'] ?? categoryOfCommodity(name))?.toString();
                                final unit = (data['unit'] ?? '').toString();
                                final effectiveDate = data['effectiveDate'] as Timestamp?;
                                final source = (data['source'] ?? '').toString();

                                return DataRow(cells: [
                                  DataCell(Text(name)),
                                  DataCell(Text(category ?? '—', style: TextStyle(color: c.textSecondary))),
                                  DataCell(Text(
                                    liveAverage != null
                                        ? _formatPriceWithUnit(liveAverage, unit)
                                        : 'No active retail listings',
                                    style: TextStyle(color: c.textSecondary),
                                  )),
                                  DataCell(Text(
                                    wholesaleLiveAverage != null
                                        ? _formatPriceWithUnit(wholesaleLiveAverage, unit)
                                        : 'No wholesale market data yet',
                                    style: TextStyle(color: c.textSecondary),
                                  )),
                                  DataCell(Text(_formatPriceWithUnit(baseline, unit),
                                      style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text(unit.isEmpty ? 'kg' : unit, style: TextStyle(color: c.textSecondary))),
                                  DataCell(Text(
                                    effectiveDate != null ? DateFormat('MMM d, y').format(effectiveDate.toDate()) : '—',
                                    style: TextStyle(color: c.textSecondary),
                                  )),
                                  DataCell(Text(source.isEmpty ? '—' : source, style: TextStyle(color: c.textSecondary))),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Update reference price',
                                        icon: Icon(Icons.edit_outlined, size: 18, color: c.textSecondary),
                                        onPressed: () => _openBaselineDialog(
                                          context,
                                          commodityId: doc.id,
                                          name: name,
                                          price: baseline,
                                          unit: unit,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove reference price',
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
          ),
        ],
      ),
    );
  }
}

// Shown after a price file is read and validated, before anything is
// written — the admin sees every row (valid and invalid, with a specific
// reason for each rejection) and must explicitly confirm before
// "Import Valid Rows" writes anything to Firestore.
class _PriceImportPreviewDialog extends StatelessWidget {
  final List<_PriceImportRow> rows;
  final String fileName;

  const _PriceImportPreviewDialog({required this.rows, required this.fileName});

  Widget _summaryChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validCount = rows.where((r) => r.isValid).length;
    final invalidCount = rows.length - validCount;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: screenHeight * 0.82),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Import Preview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(fileName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _summaryChip('Valid rows: $validCount', Colors.green),
                  const SizedBox(width: 8),
                  _summaryChip('Invalid rows: $invalidCount', invalidCount > 0 ? Colors.red : Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 28,
                      columns: const [
                        DataColumn(label: Text('Commodity')),
                        DataColumn(label: Text('Reference Price')),
                        DataColumn(label: Text('Effective Date')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: rows.map((row) {
                        final statusText = row.isValid
                            ? 'Valid'
                            : row.error == 'Not a supported AgriTrade+ commodity'
                                ? 'Unsupported'
                                : 'Invalid';
                        final statusCell = Text(
                          statusText,
                          style: TextStyle(
                            color: row.isValid ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                        return DataRow(cells: [
                          DataCell(Text(row.displayName)),
                          DataCell(Text(
                            row.referencePrice != null ? _formatPriceWithUnit(row.referencePrice!, row.unit) : '—',
                          )),
                          DataCell(Text(
                            row.effectiveDate != null ? DateFormat('MMM d, y').format(row.effectiveDate!) : '—',
                          )),
                          DataCell(row.isValid ? statusCell : Tooltip(message: row.error!, child: statusCell)),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (invalidCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  "Hover an invalid row's status for the reason. Only valid rows will be imported.",
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: validCount > 0 ? () => Navigator.of(context).pop(true) : null,
                    child: Text(validCount > 0 ? 'Import Valid Rows ($validCount)' : 'Import Valid Rows'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BaselinePriceDialog extends StatefulWidget {
  final String? commodityId;
  final String? initialName;
  final double? initialPrice;
  final String? initialUnit;

  const _BaselinePriceDialog({this.commodityId, this.initialName, this.initialPrice, this.initialUnit});

  @override
  State<_BaselinePriceDialog> createState() => _BaselinePriceDialogState();
}

class _BaselinePriceDialogState extends State<_BaselinePriceDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName ?? '');
  late final TextEditingController _priceController =
      TextEditingController(text: widget.initialPrice != null ? widget.initialPrice!.toStringAsFixed(2) : '');
  late final TextEditingController _unitController =
      TextEditingController(text: (widget.initialUnit == null || widget.initialUnit!.isEmpty) ? 'kg' : widget.initialUnit);

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
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final unit = _unitController.text.trim();

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

      final oldPrice = existing.data()?['baselinePrice'];
      await docRef.set({
        'name': name,
        'category': categoryOfCommodity(name),
        'baselinePrice': price,
        'unit': unit.isEmpty ? 'kg' : unit,
        'previousBaselinePrice': oldPrice,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid ??
            'admin',
      }, SetOptions(merge: true));

      AuditLogService.log(
        AuditAction.updateBaselinePrice,
        oldPrice is num
            ? '$name: ${formatPeso(oldPrice)} → ${formatPeso(price)}'
            : '$name: set to ${formatPeso(price)}',
      );

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
      title: Text(widget.commodityId == null ? 'Set Admin Reference Price' : 'Update Admin Reference Price'),
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
              decoration: const InputDecoration(labelText: 'Admin reference price (₱)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'e.g. kg, piece, kg liveweight',
              ),
            ),
            const SizedBox(height: 10),
            // Shows what active Farmer listings say right now, right next
            // to the reference price the admin is about to commit — the
            // two are always kept visibly separate (never averaged together).
            Text(
              _loadingProducts
                  ? 'Checking active listings…'
                  : liveAverage != null
                      ? 'Current market average right now: ${formatPeso(liveAverage)}'
                      : 'No active listings match this name yet.',
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
