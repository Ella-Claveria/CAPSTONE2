import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter/foundation.dart'
    show kDebugMode, debugPrint, ValueListenable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/commodity_master_list.dart';
import '../theme/app_theme.dart';
import 'verification_queue_view.dart';
import 'farmer_list_view.dart';
import 'moderation_queue_view.dart';
import '../data/laurel_barangays.dart';
import '../services/connectivity_service.dart';
import '../services/market_price_helpers.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/agri_dialog.dart'
    show AgriTone, agriBarrierColor, showAgriConfirm;
import '../services/pdf_report_service.dart';
import '../services/admin_perf.dart';
import '../services/admin_session_service.dart';
import '../services/audit_log_service.dart';
import '../services/dashboard_analytics_service.dart';
import '../services/dashboard_data_service.dart';
import '../services/dashboard_overview_service.dart';
import '../services/geocoding_service.dart';
import '../services/trackpad_pan_io.dart'
    if (dart.library.js_interop) '../services/trackpad_pan_web.dart';
import '../widgets/chart_capture_boundary.dart';
import 'admin_filter_controls.dart';
import 'admin_suspend_accounts_dialog.dart';
import 'admin_global_search.dart';
import 'admin_market_trends_card.dart';
import 'admin_notifications.dart';
import 'admin_account_views.dart';
import 'admin_info_dialogs.dart';
import 'admin_analytics_widgets.dart';
import 'admin_demand_widgets.dart';
import 'admin_overview_widgets.dart';
import 'admin_user_accounts_view.dart';
import 'admin_sub_nav.dart';
import 'audit_log_view.dart';
import 'export_options_dialog.dart';
import 'login_screen.dart';
import 'admin_session_gate.dart';
import '../services/auth_routing_service.dart';

// ============================================================
// THEME — a small self-contained palette (light only) so this
// screen doesn't depend on the app's global ThemeData.
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

  // The portal's only theme. [isDark] stays on the palette (always false)
  // so the widgets that read it keep working.
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

  /// Buttons, toggles and chips are pill-shaped everywhere in the portal
  /// except the sidebar, whose items are tabs.
  static const double pill = 999;
}

/// Provides the current [AdminPalette] to the whole admin subtree, so any
/// descendant widget can read `AdminThemeScope.of(context).palette`
/// without prop-drilling.
class AdminThemeScope extends InheritedWidget {
  final AdminPalette palette;

  const AdminThemeScope({
    super.key,
    required this.palette,
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
  _NavItem(
    Icons.dashboard_outlined,
    Icons.dashboard_rounded,
    'Analytics Dashboard',
  ),
  _NavItem(Icons.map_outlined, Icons.map_rounded, 'Demand Heatmap'),
  _NavItem(
    Icons.verified_user_outlined,
    Icons.verified_user_rounded,
    'Verification Queue',
  ),
  _NavItem(Icons.groups_outlined, Icons.groups_rounded, 'User Accounts'),
  _NavItem(
    Icons.price_change_outlined,
    Icons.price_change_rounded,
    'Price Management',
  ),
  _NavItem(Icons.gavel_outlined, Icons.gavel_rounded, 'Moderation Queue'),
  _NavItem(Icons.report_outlined, Icons.report_rounded, 'Violations'),
  _NavItem(Icons.fact_check_outlined, Icons.fact_check_rounded, 'Audit Log'),
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
  // ---- Access is re-checked for as long as the dashboard is open ----
  // The check at the door (AdminSessionGate / login) only covers the
  // moment of entry. These two listeners cover everything after it: the
  // session ending somewhere else (Logout in another tab, a revoked or
  // expired session), and the account losing its Admin role or being
  // suspended. Either one closes the dashboard and returns to login.
  // Firestore rules already refuse the data in those cases; this makes
  // the screen follow.
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _accountSub;
  bool _leaving = false;

  // One active Admin session per account (see AdminSessionService): the
  // moment this browser's session stops being the active one — the
  // account signed in on another device — the dashboard closes, without
  // waiting for a refresh. The timer says the session is still in use.
  StreamSubscription<void>? _sessionSub;
  Timer? _sessionHeartbeat;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _leave('Your session has ended. Please log in again.');
      } else if (user.uid != uid) {
        // Another account signed in from another tab of this browser: it
        // has to pass the door check itself.
        _leaveToGate();
      }
    });
    if (uid == null) return;
    _sessionSub = AdminSessionService.watchEnded(
      uid,
    ).listen((_) => _leaveSessionEnded(uid), onError: (_) {});
    AdminSessionService.touch(uid);
    _sessionHeartbeat = Timer.periodic(
      AdminSessionService.heartbeat,
      (_) => AdminSessionService.touch(uid),
    );
    _accountSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
          // Only the server's word counts — a cached copy may be stale.
          if (snap.metadata.isFromCache) return;
          if (await _revokedHere(snap.data())) {
            await _leaveSessionEnded(uid, revoked: true);
            return;
          }
          final lost = AuthRoutingService.adminAccessLostReason(
            snap.exists ? snap.data() : null,
          );
          if (lost == null || _leaving) return;
          _leaving = true;
          debugPrint(
            '[Auth] signOut() called — reason: admin access lost '
            '($lost, uid: $uid)',
          );
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          _leaving = false;
          _leave('This account no longer has administrator access.');
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _accountSub?.cancel();
    _sessionSub?.cancel();
    _sessionHeartbeat?.cancel();
    super.dispose();
  }

  // The account signed in on another device — or, with [revoked], this
  // browser was signed out from Active Sessions on another one: it is
  // signed out and returned to login, where a popup says why.
  Future<void> _leaveSessionEnded(String uid, {bool revoked = false}) async {
    if (_leaving) return;
    _leaving = true;
    _authSub?.cancel();
    _authSub = null;
    _accountSub?.cancel();
    _accountSub = null;
    _sessionSub?.cancel();
    _sessionSub = null;
    _sessionHeartbeat?.cancel();
    // Logged while still signed in, and never allowed to hold the
    // sign-out back. A revoked browser can no longer log anything: the
    // revocation itself is in the Audit Log (SESSION_REVOKED).
    if (!revoked) {
      try {
        await AuditLogService.log(
          AuditAction.sessionForcedLogout,
          'This Admin session was ended because the account logged in on '
          'another device.',
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    await AdminSessionService.clearLocal(uid);
    debugPrint(
      '[Auth] signOut() called — reason: Admin session '
      '${revoked ? 'revoked from Active Sessions' : 'replaced on another device'} '
      '(uid: $uid)',
    );
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          role: 'admin',
          adminSessionEnded: true,
          adminSessionRevoked: revoked,
        ),
      ),
      (route) => false,
    );
  }

  // Whether this browser was signed in before the account's sessions were
  // revoked (sessionsValidAfter, set by Active Sessions > Revoke Session):
  // it is the one signed out. firestore.rules already refuses it.
  Future<bool> _revokedHere(Map<String, dynamic>? account) async {
    final validAfter = account?['sessionsValidAfter'];
    if (validAfter is! Timestamp) return false;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      final signedIn = token?.authTime;
      return signedIn != null && signedIn.isBefore(validAfter.toDate());
    } catch (_) {
      return false;
    }
  }

  // Replaces the dashboard (the only route on the stack) with the admin
  // login page, so browser Back has nothing protected to return to.
  void _leave(String? message) {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(role: 'admin', flashMessage: message),
      ),
      (route) => false,
    );
  }

  void _leaveToGate() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminSessionGate()),
      (route) => false,
    );
  }

  // True once the portal has gone back to the login page.
  Future<bool> _logout() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // Both must happen while still signed in — the Cloud Functions need
      // an authenticated caller: the Audit Log entry, and the end of this
      // browser's session (so the next login has nothing to replace).
      // Together, best-effort and bounded: a slow or failing call must
      // never keep the admin signed in, or the Logout button waiting.
      try {
        await Future.wait([
          AuditLogService.log(
            AuditAction.logout,
            'Logged out of the Admin Portal.',
            locationWait: Duration.zero,
          ),
          if (uid != null) AdminSessionService.end(uid),
        ]).timeout(const Duration(seconds: 3));
      } catch (_) {}
      debugPrint(
        '[Auth] signOut() called — reason: admin tapped Logout '
        '(uid: ${FirebaseAuth.instance.currentUser?.uid})',
      );
      // Signing out fires the auth listener above, which would show the
      // "session has ended" notice — this is a plain logout, so go to the
      // login page without one.
      _authSub?.cancel();
      _authSub = null;
      _accountSub?.cancel();
      _accountSub = null;
      _sessionSub?.cancel();
      _sessionSub = null;
      _sessionHeartbeat?.cancel();
      await FirebaseAuth.instance.signOut();
      _leave(null);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  late final List<Widget> _pages = [
    const _AnalyticsDashboardView(),
    const _DemandHeatmapView(),
    const VerificationQueueView(),
    const _UserAccountsPage(),
    const _PriceManagementView(),
    const ModerationQueueView(),
    const ModerationQueueView(violations: true),
    const AuditLogView(),
  ];

  @override
  Widget build(BuildContext context) {
    // The portal has one theme: light.
    const palette = AdminPalette.light;

    return AdminThemeScope(
      palette: palette,
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: palette.isDark ? Brightness.dark : Brightness.light,
            primary: palette.green,
            surface: palette.surface,
            onSurface: palette.textPrimary,
          ),
          scaffoldBackgroundColor: palette.bg,
          // Montserrat with its real weights (see kAdminFontFamily), so
          // that bold text is bold in a browser too.
          textTheme: Theme.of(
            context,
          ).textTheme.apply(fontFamily: kAdminFontFamily),
          primaryTextTheme: Theme.of(
            context,
          ).primaryTextTheme.apply(fontFamily: kAdminFontFamily),
          // System messages: the app's dark green, white-text bar, as a
          // compact box centred at the bottom instead of a bar across the
          // whole window (a narrow window keeps the full-width one).
          snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
            width: MediaQuery.sizeOf(context).width >= 520 ? 460 : null,
            contentTextStyle: Theme.of(context).snackBarTheme.contentTextStyle
                ?.copyWith(fontFamily: kAdminFontFamily),
          ),
          // Every button in the portal is pill-shaped (the sidebar's items
          // are tabs, not buttons). Elevated buttons already are, from the
          // app's own theme; this covers the rest, dialogs included.
          // …and, in every dialog, the same colours and font: the main
          // button dark green with white text, the others dark green text.
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              foregroundColor: adminActionColor(palette),
              side: BorderSide(color: palette.border),
              textStyle: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              shape: const StadiumBorder(),
              foregroundColor: adminActionColor(palette),
              textStyle: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              backgroundColor: adminActionColor(palette),
              foregroundColor: adminOnActionColor(palette),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              textStyle: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: const StadiumBorder(),
              elevation: 0,
              backgroundColor: adminActionColor(palette),
              foregroundColor: adminOnActionColor(palette),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              textStyle: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            // Pill-shaped, like the buttons. A field tall enough for
            // several lines keeps a rounded corner instead (see
            // adminMultilineBorder), where a pill would crowd the text.
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminRadii.pill),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminRadii.pill),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminRadii.pill),
              borderSide: BorderSide(color: palette.green, width: 1.5),
            ),
          ),
          // Tick boxes (a table's row selection): dark green when ticked.
          checkboxTheme: CheckboxThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            // A ticked box keeps an outline in the tick's colour, so the
            // select-all box still shows on the dark green table header.
            side: WidgetStateBorderSide.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? adminOnActionColor(palette)
                    : palette.textMuted,
                width: 1.4,
              ),
            ),
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? adminActionColor(palette)
                  : Colors.transparent,
            ),
            checkColor: WidgetStatePropertyAll(adminOnActionColor(palette)),
          ),
          // Any other progress sign in the portal: the same dark green.
          progressIndicatorTheme: ProgressIndicatorThemeData(
            color: adminActionColor(palette),
            linearTrackColor: palette.surfaceAlt,
            circularTrackColor: Colors.transparent,
          ),
          // Menus and dialogs: the mobile app's popup card — rounded,
          // thin border, soft shadow, over a lightly dimmed page.
          popupMenuTheme: PopupMenuThemeData(
            color: palette.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAdminPopupRadius),
              side: BorderSide(color: palette.border),
            ),
            textStyle: GoogleFonts.montserrat(
              color: palette.textPrimary,
              fontSize: 13,
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: palette.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            barrierColor: agriBarrierColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kAdminPopupRadius),
              side: BorderSide(color: palette.border),
            ),
            titleTextStyle: GoogleFonts.montserrat(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.isDark ? palette.textPrimary : AppTheme.dark,
            ),
            contentTextStyle: GoogleFonts.montserrat(
              fontSize: 13,
              height: 1.45,
              color: palette.textPrimary,
            ),
          ),
        ),
        child: Scaffold(
          backgroundColor: palette.bg,
          body: _AdminShell(pages: _pages, onLogout: _logout),
        ),
      ),
    );
  }
}

// ============================================================
// SHELL — the sidebar, the utility bar and the content area.
//
// Tab selection lives here, in two ValueNotifiers, rather than in
// AdminDashboardScreen's setState: a click must not rebuild the theme,
// the Scaffold or anything else around the two.
//
//  * [_selected] drives ONLY the sidebar's active item. It changes
//    synchronously on click, so the highlight is on screen in the very
//    next frame, before the destination page has done any work.
//  * [_shown] drives ONLY the content area. It follows one frame later,
//    so a heavy page build (charts, tables, the map) can never hold the
//    highlight back.
//
// Pages are built the first time their tab is opened and then kept
// mounted in an IndexedStack: going back to one is a single cheap frame,
// with its Firestore listeners, loaded data, scroll position and filters
// intact — nothing is torn down, re-subscribed or re-fetched. Each page
// shows its own loading state while its data arrives.
// ============================================================
class _AdminShell extends StatefulWidget {
  final List<Widget> pages;
  final Future<bool> Function() onLogout;
  const _AdminShell({required this.pages, required this.onLogout});

  @override
  State<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<_AdminShell> {
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);
  final ValueNotifier<int> _shown = ValueNotifier<int>(0);
  final Set<int> _visited = {0};

  // Pages that read DashboardDataService's cached analytics fetch
  // (Analytics Dashboard, Demand Heatmap, User Accounts, Price
  // Management).
  static const Set<int> _cachedDataPages = {0, 1, 3, 4};

  // Switching between light and dark repaints every page that is being
  // kept alive in the background, not just the one on screen — tables,
  // charts and the map all at once, which made the switch slow. So the
  // background pages are let go when the theme changes: only the open
  // page is redrawn now, and each of the others is built again, in the
  // new theme, the next time it is opened (its data is already cached).
  bool? _wasDark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = AdminThemeScope.of(context).palette.isDark;
    if (_wasDark != null && _wasDark != isDark) {
      _visited
        ..clear()
        ..add(_shown.value);
    }
    _wasDark = isDark;
  }

  // The Admin folded the full sidebar into the icon rail (its sidebar
  // button, or Ctrl+Shift+S). Remembered on this browser.
  bool _userCollapsed = false;
  static const _collapsedKey = 'admin_sidebar_collapsed';
  static const _toggleShortcut = 'Ctrl+Shift+S';

  // The window's width at the last build, for the keyboard shortcut.
  double _width = double.infinity;

  @override
  void initState() {
    super.initState();
    adminOpenPageRequest.addListener(_openRequestedPage);
    HardwareKeyboard.instance.addHandler(_onKey);
    _loadCollapsed();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    adminOpenPageRequest.removeListener(_openRequestedPage);
    _selected.dispose();
    _shown.dispose();
    super.dispose();
  }

  Future<void> _loadCollapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_collapsedKey) ?? false;
      if (mounted && collapsed != _userCollapsed) {
        setState(() => _userCollapsed = collapsed);
      }
    } catch (_) {
      // No saved choice: the sidebar starts open.
    }
  }

  // Ctrl+Shift+S (Cmd+Shift+S on a Mac) opens or closes the sidebar.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyS) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (!keys.isShiftPressed ||
        !(keys.isControlPressed || keys.isMetaPressed) ||
        keys.isAltPressed) {
      return false;
    }
    _toggleSidebar();
    return true;
  }

  // A wide window folds the sidebar into the rail or opens it back out,
  // pushing the page over. A narrower one, where there is no room for
  // both, opens the full sidebar over the page instead (and closes it).
  void _toggleSidebar() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    if (_width >= _sidebarFrom) {
      setState(() => _userCollapsed = !_userCollapsed);
      final collapsed = _userCollapsed;
      unawaited(
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool(_collapsedKey, collapsed))
            .catchError((_) => false),
      );
    } else {
      scaffold?.openDrawer();
    }
  }

  // A notification was clicked: open the page it is about.
  void _openRequestedPage() {
    final target = adminOpenPageRequest.value;
    if (target == null) return;
    adminOpenPageRequest.value = null;
    // About a farmer: User Accounts › Farmers, even if Buyers was open.
    if (target == AdminNotificationTarget.farmers) {
      AdminSubNav.accounts.value = UserAccountsSection.farmers;
    }
    _goTo(switch (target) {
      AdminNotificationTarget.heatmap => _heatmapPage,
      AdminNotificationTarget.verification => _verificationPage,
      AdminNotificationTarget.farmers => _accountsPage,
      AdminNotificationTarget.moderation => _moderationPage,
      AdminNotificationTarget.auditLog => _auditLogPage,
    });
  }

  void _goTo(int index) {
    if (index == _selected.value) return;
    final label = _navItems[index].label;
    final watch = Stopwatch()..start();
    debugPrint('[AdminNav] click → $label');

    // 1. Active tab highlight — immediately, nothing else.
    _selected.value = index;

    // 2. Content — one frame later, once the highlight has been drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        '[AdminNav] $label: tab highlight drawn in '
        '${watch.elapsedMilliseconds} ms',
      );
      // Clicked on to another tab in the meantime — that click has its own
      // callback.
      if (!mounted || _selected.value != index) return;
      final firstVisit = _visited.add(index);
      // A kept-alive page doesn't rebuild on return, so its own
      // ensureLoaded() no longer runs — keep the 5-minute cache refresh it
      // used to get. No Firestore read while the cache is still fresh.
      if (!firstVisit && _cachedDataPages.contains(index)) {
        DashboardDataService.instance.ensureLoaded();
      }
      final buildWatch = Stopwatch()..start();
      _shown.value = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A slow FIRST visit is that page building itself; a slow REPEAT
        // visit would mean something is rebuilding that shouldn't be.
        // Firestore timings are logged separately ([AdminData]/[Overview]).
        debugPrint(
          '[AdminNav] $label: page on screen in '
          '${buildWatch.elapsedMilliseconds} ms '
          '(${firstVisit ? 'first visit — page built' : 'kept alive — not rebuilt'}), '
          '${watch.elapsedMilliseconds} ms since click',
        );
      });
    });
    // Make sure that next frame actually happens.
    WidgetsBinding.instance.scheduleFrame();
  }

  // Window widths the navigation changes shape at: the full sidebar from
  // [_sidebarFrom] up, the icon-only rail from [_railFrom], and below that
  // a drawer opened from the utility bar.
  static const double _sidebarFrom = 1100;
  static const double _railFrom = 700;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // The sidebar in any of its three shapes. Only this rebuilds when the
  // active page changes.
  Widget _sidebar({required bool collapsed, bool inDrawer = false}) {
    return RepaintBoundary(
      // Also rebuilt when a page changes its own section (a Moderation tab
      // clicked in the page), so the submenu's highlight follows.
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _selected,
          AdminSubNav.accounts,
          AdminSubNav.moderation,
          AdminSubNav.violations,
          AdminSubNav.audit,
        ]),
        builder: (context, _) => AdminSidebar(
          entries: _sidebarEntries,
          selectedIndex: _selected.value,
          // The Admin account, with Logout in its menu, pinned at the
          // bottom.
          footer: Padding(
            padding: collapsed
                ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
                : const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: _AdminAccountMenu(
              onLogout: widget.onLogout,
              collapsed: collapsed,
            ),
          ),
          selectedChildIndex: switch (_selected.value) {
            _accountsPage => AdminSubNav.accounts.value.index,
            _moderationPage => AdminSubNav.moderation.value.index,
            _violationsPage => AdminSubNav.violations.value.index,
            _auditLogPage => AdminSubNav.audit.value.index,
            _ => null,
          },
          collapsed: collapsed,
          onToggleCollapsed: _toggleSidebar,
          toggleShortcut: _toggleShortcut,
          onSelect: (index) {
            if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
            _goTo(index);
          },
          onSelectChild: (index, child) {
            if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
            switch (index) {
              case _accountsPage:
                AdminSubNav.accounts.value = UserAccountsSection.values[child];
              case _moderationPage:
                AdminSubNav.moderation.value = ModerationSection.values[child];
              case _violationsPage:
                AdminSubNav.violations.value = ViolationSection.values[child];
              case _auditLogPage:
                AdminSubNav.audit.value = AuditSection.values[child];
            }
            _goTo(index);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _width = width;
        final useDrawer = width < _railFrom;
        // Too narrow for the full sidebar beside the page: the rail, whose
        // sidebar button opens the full one over the page.
        final narrow = width < _sidebarFrom;
        // One Scaffold in every shape, and the content keyed, so resizing
        // the window never rebuilds the pages.
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          // Dragging from the edge opens it only where there is no rail.
          drawerEnableOpenDragGesture: useDrawer,
          drawer: narrow
              ? Drawer(
                  width: AdminSidebar.expandedWidth,
                  backgroundColor: AdminSidebarColors.light.background,
                  shape: const RoundedRectangleBorder(),
                  child: _sidebar(collapsed: false, inDrawer: true),
                )
              : null,
          body: Row(
            children: [
              // Fixed: only the content to its right changes or scrolls.
              if (!useDrawer) _sidebar(collapsed: narrow || _userCollapsed),
              Expanded(
                key: const ValueKey('admin-content'),
                child: Column(
                  children: [
                    _AdminUtilityBar(
                      selected: _selected,
                      onGoHome: () => _goTo(0),
                      showBrand: width < _sidebarFrom,
                      onOpenMenu: useDrawer
                          ? () => _scaffoldKey.currentState?.openDrawer()
                          : null,
                    ),
                    Expanded(
                      child: RepaintBoundary(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _shown,
                          builder: (context, shown, _) => IndexedStack(
                            index: shown,
                            sizing: StackFit.expand,
                            children: [
                              for (var i = 0; i < widget.pages.length; i++)
                                // Not opened yet: an empty placeholder, so
                                // nothing loads until its page is opened.
                                // Hidden pages have their animations paused.
                                _visited.contains(i)
                                    ? TickerMode(
                                        enabled: i == shown,
                                        child: widget.pages[i],
                                      )
                                    : const SizedBox.shrink(),
                            ],
                          ),
                        ),
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
  }
}

// The notification bell and its feed are in admin_notifications.dart.

// ============================================================
// The Dashboard's welcome banner: the greeting, today's date, and the
// banner picture on the right.
// ============================================================

/// The banner picture. Until the file is added to the project (and listed
/// under assets in pubspec.yaml) the banner simply shows without it.
const String kAdminDashboardBanner = 'assets/images/admin_dashboard_banner.png';

class _DashboardWelcome extends StatefulWidget {
  const _DashboardWelcome();

  @override
  State<_DashboardWelcome> createState() => _DashboardWelcomeState();
}

class _DashboardWelcomeState extends State<_DashboardWelcome> {
  // Ticks the clock in the banner once a second.
  late final Timer _clock = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() => _now = DateTime.now()),
  );
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock; // Starts it.
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final today = _now;

    final date = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.greenBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${today.day}',
            style: TextStyle(
              color: c.green,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('MMM y').format(today),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              DateFormat('EEE').format(today),
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
          ],
        ),
        Container(
          width: 1,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          color: c.border,
        ),
        // Fixed-width digits, so the time does not shift as it ticks.
        Text(
          DateFormat('h:mm:ss a').format(today),
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'ADMIN DASHBOARD',
          style: TextStyle(
            color: c.green,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Welcome back, Admin!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "Here's what's happening with AgriTrade+ today.",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        return Container(
          height: wide ? 118 : null,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 22),
                    Expanded(flex: 5, child: greeting),
                    const SizedBox(width: 20),
                    // The picture, shown exactly as supplied: scaled to the
                    // banner's height.
                    Expanded(
                      flex: 6,
                      child: Image.asset(
                        kAdminDashboardBanner,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    // Today's date and the time, in the right corner.
                    const SizedBox(width: 20),
                    Center(child: date),
                    const SizedBox(width: 22),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [greeting, const SizedBox(height: 14), date],
                  ),
                ),
        );
      },
    );
  }
}

// ============================================================
// NAVIGATION — the pages are listed in the dark green sidebar on the left
// (AdminSidebar: full on a desktop window, an icon rail on a tablet-sized
// one, a drawer on a phone-sized one). Above the content, on every page,
// sits the same curved header with the open page's title and the
// notification bell — no page links of its own. The Admin account is at
// the bottom of the sidebar.
// ============================================================

// Short captions for the sidebar, by index into _navItems (whose own
// labels stay the full page names used in logs).
const List<String> _topNavLabels = [
  'Dashboard',
  'Demand Heatmap',
  'Verification',
  'User Accounts',
  'Price Management',
  'Moderation',
  'Violations',
  'Audit Log',
];

// Each page's title, by index into _navItems, shown in the utility bar
// above the page rather than inside it.
const List<String> _pageTitles = [
  'Analytics Dashboard',
  'Demand Heatmap',
  'Verification Queue',
  'User Accounts',
  'Commodity Price Management',
  'Moderation Queue',
  'Violations',
  'Audit Log',
];

// Pages with several views of their own, by index into _navItems: the
// sidebar lists those views as a submenu. Only views that exist — a
// User Accounts section, a Moderation tab, an Audit Log section (see
// AdminSubNav).
const int _verificationPage = 2;
const int _accountsPage = 3;
const int _moderationPage = 5;
const int _violationsPage = 6;
const int _auditLogPage = 7;
const int _heatmapPage = 1;

final List<AdminSidebarEntry> _sidebarEntries = [
  for (var i = 0; i < _navItems.length; i++)
    AdminSidebarEntry(
      _navItems[i].icon,
      _topNavLabels[i],
      children: switch (i) {
        _accountsPage => [
          for (final section in UserAccountsSection.values) section.label,
        ],
        _moderationPage => [
          for (final section in ModerationSection.values) section.label,
        ],
        _violationsPage => [
          for (final section in ViolationSection.values) section.label,
        ],
        _auditLogPage => [
          for (final section in AuditSection.values) section.label,
        ],
        _ => const [],
      },
    ),
];

class _AdminUtilityBar extends StatelessWidget {
  /// Non-null on a phone-sized window, where the sidebar is a drawer:
  /// shows the menu button that opens it.
  final VoidCallback? onOpenMenu;

  /// The page whose title the bar shows.
  final ValueListenable<int> selected;

  /// The sidebar is not showing the AgriTrade+ wordmark (icon rail or
  /// drawer), so the header carries it instead.
  final bool showBrand;

  /// "Dashboard" in the breadcrumb was clicked.
  final VoidCallback onGoHome;

  const _AdminUtilityBar({
    required this.selected,
    required this.onGoHome,
    this.onOpenMenu,
    this.showBrand = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    // Only this rebuilds when the page, or the section open in it, changes.
    return ListenableBuilder(
      listenable: Listenable.merge([
        selected,
        AdminSubNav.accounts,
        AdminSubNav.moderation,
        AdminSubNav.violations,
        AdminSubNav.audit,
      ]),
      // The Dashboard greets the Admin in its own banner, so there is no
      // title under the bar there.
      builder: (context, _) {
        final index = selected.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(c, index),
            if (index != 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 10),
                child: Text(
                  _pageTitles[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Where the Admin is: Dashboard › the page › the section open in it.
  // "Dashboard" goes back there; the last one is where they are now.
  Widget _breadcrumb(AdminPalette c, int page) {
    final section = switch (page) {
      _accountsPage => AdminSubNav.accounts.value.label,
      _moderationPage => AdminSubNav.moderation.value.label,
      _violationsPage => AdminSubNav.violations.value.label,
      _auditLogPage => AdminSubNav.audit.value.label,
      _ => null,
    };
    final trail = [
      _topNavLabels[0],
      if (page != 0) _topNavLabels[page],
      // A section named like its page ("Violations") is not said twice.
      if (section != null && section != _topNavLabels[page]) section,
    ];
    TextStyle style(bool current) => TextStyle(
      fontSize: 13,
      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
      color: current ? c.textPrimary : c.textSecondary,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < trail.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: c.textMuted,
                ),
              ),
            if (i == 0 && trail.length > 1)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onGoHome,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: Text(trail[i], style: style(false)),
                ),
              )
            else
              Text(trail[i], style: style(i == trail.length - 1)),
          ],
        ],
      ),
    );
  }

  Widget? _menuButton(AdminPalette c) => onOpenMenu == null
      ? null
      : IconButton(
          tooltip: 'Menu',
          onPressed: onOpenMenu,
          icon: Icon(Icons.menu_rounded, color: c.textPrimary),
        );

  // The same bar on every page: where the Admin is on the left, then the
  // search, Announce and the notification bell on the right (the Admin
  // account is at the bottom of the sidebar). The page's title is on its
  // own line under it.
  Widget _header(AdminPalette c, int page) {
    return Padding(
      padding: EdgeInsets.fromLTRB(onOpenMenu == null ? 24 : 10, 14, 24, 8),
      child: Row(
        children: [
          ?_menuButton(c),
          if (showBrand) ...[
            Image.asset(
              'assets/images/logo.png',
              height: 34,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.agriculture_rounded, color: c.green, size: 26),
            ),
            const SizedBox(width: 4),
            Text(
              'AgriTrade+',
              style: AppTheme.brandText(fontSize: 19).copyWith(
                // The wordmark's own dark green would not show on the dark
                // theme's surface.
                color: c.isDark ? c.textPrimary : null,
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _breadcrumb(c, page),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: 360, child: AdminGlobalSearch(page: page)),
            ),
          ),
          const SizedBox(width: 12),
          const AdminAnnounceButton(),
          const SizedBox(width: 8),
          const AdminNotificationBell(),
        ],
      ),
    );
  }
}

/// The Admin account at the bottom of the sidebar — avatar, name and
/// "Administrator" (the avatar alone on the icon rail) — and its menu: who
/// is signed in, Manage Account, Suspend Accounts, System Maintenance, the
/// information popups (admin_info_dialogs.dart) and Logout. Account
/// settings themselves are in Manage Account.
class _AdminAccountMenu extends StatefulWidget {
  final Future<bool> Function() onLogout;

  /// On the icon rail: the avatar only, and the menu opens to its right.
  final bool collapsed;

  const _AdminAccountMenu({required this.onLogout, this.collapsed = false});

  @override
  State<_AdminAccountMenu> createState() => _AdminAccountMenuState();
}

class _AdminAccountMenuState extends State<_AdminAccountMenu> {
  bool _hovered = false;

  // The menu's height (its header, seven 42 px items, three dividers and
  // its padding), so it can open above the button at the bottom of the
  // screen instead of covering it.
  static const double _menuHeight = 420;
  static const double _buttonHeight = 48;

  Future<bool> Function() get onLogout => widget.onLogout;

  // Asks first; then keeps a "Logging out…" notice up while the logout is
  // recorded and the session ended, so the click is seen to have worked.
  // The question is the mobile app's own logout popup (showAgriConfirm,
  // as in Farmer Profile and the buyer's marketplace), so both look alike.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showAgriConfirm(
      context: context,
      icon: Icons.logout,
      tone: AgriTone.destructive,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
    );
    if (!confirmed || !context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 6),
                Text('Logging out…'),
                SizedBox(height: 16),
                AdminLoadingBar(),
                SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
    // Going back to the login page takes the notice with it; it is only
    // closed here when the logout did not go through.
    final left = await onLogout();
    if (!left && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    // The signed-in Admin's photo, or their initials ("AD" until their
    // name is known, or when none is stored).
    Widget avatar(double radius, AdminProfile? profile) {
      final initials = profile == null || profile.name == 'Admin'
          ? 'AD'
          : adminInitials(profile.name);
      final url = (profile?.photoUrl ?? '').trim();
      return CircleAvatar(
        radius: radius,
        backgroundColor: c.greenBg,
        foregroundImage: url.isEmpty ? null : NetworkImage(url),
        onForegroundImageError: url.isEmpty ? null : (_, _) {},
        child: Text(
          initials.isEmpty ? 'AD' : initials,
          style: TextStyle(
            color: c.green,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.66,
          ),
        ),
      );
    }

    // Asked again after Edit Profile, so a new name shows straight away.
    Widget withProfile(Widget Function(AdminProfile? profile) builder) =>
        ValueListenableBuilder<int>(
          valueListenable: adminProfileChanged,
          builder: (context, _, _) => FutureBuilder<AdminProfile>(
            future: adminProfile(),
            builder: (context, snapshot) => builder(snapshot.data),
          ),
        );

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 42,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? c.iconInactive),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? c.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    final collapsed = widget.collapsed;
    return PopupMenuButton<String>(
      tooltip: collapsed ? 'Account' : '',
      position: PopupMenuPosition.over,
      // Above the button in the full sidebar; beside it, bottoms lined
      // up, on the rail.
      offset: collapsed
          ? const Offset(
              AdminSidebar.collapsedWidth - 4,
              -(_menuHeight - _buttonHeight),
            )
          : const Offset(0, -(_menuHeight + 8)),
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 290),
      onSelected: (value) {
        switch (value) {
          case 'manage':
            showAdminManageAccount(context);
          case 'suspend':
            showAdminSuspendAccounts(context);
          case 'maintenance':
            showAdminMaintenanceDialog(context);
          case 'terms':
            showAdminTermsPrivacy(context);
          case 'help':
            showAdminHelp(context);
          case 'about':
            showAdminAbout(context);
          case 'logout':
            _confirmLogout(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: withProfile(
            (profile) => Row(
              children: [
                avatar(21, profile),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? 'Admin',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Administrator',
                        style: GoogleFonts.montserrat(
                          color: c.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            color: c.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        item('manage', Icons.manage_accounts_outlined, 'Manage Account'),
        item('suspend', Icons.person_off_outlined, 'Suspend Accounts'),
        item('maintenance', Icons.engineering_outlined, 'System Maintenance'),
        const PopupMenuDivider(),
        item('terms', Icons.policy_outlined, 'Terms & Privacy'),
        item('help', Icons.help_outline_rounded, 'Help & Support'),
        item('about', Icons.info_outline_rounded, 'About AgriTrade+'),
        const PopupMenuDivider(),
        item('logout', Icons.logout_rounded, 'Logout', color: c.red),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _buttonHeight,
          padding: collapsed
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(8, 0, 6, 0),
          alignment: collapsed ? Alignment.center : null,
          decoration: BoxDecoration(
            color: AppTheme.dark.withValues(alpha: _hovered ? 0.08 : 0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: collapsed
              ? withProfile((profile) => avatar(16, profile))
              : withProfile(
                  (profile) => Row(
                    children: [
                      avatar(16, profile),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.name ?? 'Admin',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                color: c.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Administrator',
                              maxLines: 1,
                              style: GoogleFonts.montserrat(
                                color: c.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 18,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
        ),
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
    // The accent is a strip painted inside a uniformly-bordered card, NOT a
    // differently-coloured left BorderSide: Flutter refuses to paint a
    // rounded border whose sides have different colours ("A borderRadius
    // can only be given on borders with uniform colors"). In a debug build
    // that assertion aborted the card's painting after its background, so
    // every loaded card showed as an empty white box.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AdminRadii.card),
        border: Border.all(color: c.border),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: _content(c, accent),
          ),
        ],
      ),
    );
  }

  Widget _content(AdminPalette c, Color accent) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isEmpty ? c.textMuted : c.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            delta,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isEmpty ? c.textMuted : c.green,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;

  const AdminStatusBadge({
    super.key,
    required this.text,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AdminRadii.control),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AdminQuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  /// Shows a small chevron after the label: the button opens a choice of
  /// options (the Export Report buttons).
  final bool opensOptions;

  const AdminQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.opensOptions = false,
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
          backgroundColor: adminActionColor(c),
          foregroundColor: adminOnActionColor(c),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        padding: EdgeInsets.fromLTRB(14, 12, opensOptions ? 10 : 16, 12),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: c.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600),
          ),
          if (opensOptions) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: c.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Generic empty-state block reused across dashboard sections.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        // The mobile app's empty state (AgriEmptyState, as on its Orders
        // page): a small dark-green icon on a pale-green circle, a bold
        // title and a line under it.
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.greenBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: adminActionColor(c)),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: AdminLoadingBar()),
    );
  }
}

/// Shown when a dashboard stream errors out (e.g. permission denied,
/// offline with nothing cached) instead of silently rendering empty data.
class AdminStreamError extends StatelessWidget {
  static const String message =
      'Could not load this data. Check your connection and try again.';
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
              source == null
                  ? message
                  : 'Could not load $source. Check your connection and admin access.',
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
/// Market Intelligence from each other, instead of
/// relying on spacing alone.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title}) : subtitle = null;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
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
    DashboardOverviewService.instance.ensureLoaded();
    final c = AdminThemeScope.of(context).palette;
    return _buildBody(context, c);
  }

  Widget _buildBody(BuildContext context, AdminPalette c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- WELCOME ----
          const _DashboardWelcome(),

          const SizedBox(height: 22),

          // ---- 1. OVERVIEW ----
          // On their own, outside the analytics fetch below: four small
          // aggregate queries (see DashboardOverviewService), loaded once
          // and then kept current by its live listeners — so the cards
          // appear as soon as each number is back instead of waiting for
          // every order and product document to download.
          // No Refresh button: every figure below updates by itself from
          // the portal's live listeners.
          Row(
            children: [
              const Expanded(child: _SectionHeader(title: 'Overview')),
              AdminQuickActionButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Export Report',
                opensOptions: true,
                onPressed: () => _openExportDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: DashboardOverviewService.instance,
            builder: (context, _) =>
                _overviewStrip(DashboardOverviewService.instance),
          ),

          const SizedBox(height: 16),

          // Everything below is fed by DashboardDataService's cached
          // orders/products/market_prices fetch (see dashboard_data_service.
          // dart) — a one-shot .get(), not a live listener, refreshed only
          // on TTL expiry or the Refresh button above. Sales Performance
          // and Market Intelligence both read that one
          // orders snapshot, so their figures always reconcile with each
          // other.
          ListenableBuilder(
            listenable: DashboardDataService.instance,
            builder: (context, _) {
              final svc = DashboardDataService.instance;
              // Both sections are built from completed orders, so they
              // appear as soon as orders are in — not held back for the
              // product and price lists, which fill in when they arrive.
              // Until then each section is in place as a skeleton.
              if (!svc.ordersReady) {
                return svc.lastError != null
                    ? const AdminStreamError()
                    : const _DashboardSectionsSkeleton();
              }

              final orders = svc.orders;
              final products = svc.products;
              final now = DateTime.now();
              // Mapped once per data load, not once per chart rebuild.
              final orderData = [for (final d in orders) d.data()];
              final topProducts = DashboardAnalyticsService.topSellingProducts(
                orders,
              );
              // The supported commodity list (the Admin-managed one the
              // whole app uses), each matched by name to its baseline
              // price where the Admin has set one.
              final commodities = [
                for (final commodity in CommodityRegistry.instance.all)
                  commodity.name,
              ];
              final baselineByName = <String, double>{
                for (final doc in svc.marketPrices)
                  if (((doc.data()['baselinePrice'] as num?) ?? 0) > 0)
                    (doc.data()['name'] ?? doc.id)
                        .toString()
                        .trim()
                        .toLowerCase(): (doc.data()['baselinePrice'] as num)
                        .toDouble(),
              };
              final baselineByCommodity = <String, double>{
                for (final name in commodities)
                  if (baselineByName[name.toLowerCase()] != null)
                    name: baselineByName[name.toLowerCase()]!,
              };
              final weeklyPricesByCommodity = <String, List<double?>>{
                for (final name in commodities)
                  name: DashboardAnalyticsService.weeklyAveragePrice(
                    orders,
                    name,
                    now: now,
                  ),
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- 2. SALES PERFORMANCE ---- (each card is titled)
                  _responsiveRow(
                    [
                      ChartCaptureBoundary(
                        captureKey: DashboardChartKeys.salesOverview,
                        child: AdminSalesPerformanceCard(orders: orderData),
                      ),
                      ChartCaptureBoundary(
                        captureKey: DashboardChartKeys.salesByCategory,
                        child: AdminSalesByCategoryCard(
                          revenueFor: (months) =>
                              DashboardAnalyticsService.categoryRevenue(
                                orders,
                                products,
                                range:
                                    DashboardAnalyticsService.lastMonthsRange(
                                      DateTime.now(),
                                      months,
                                    ),
                              ),
                        ),
                      ),
                    ],
                    flexes: const [3, 2],
                  ),

                  const SizedBox(height: 16),

                  // ---- 3. MARKET INTELLIGENCE ---- (each card is titled)
                  _responsiveRow(
                    [
                      ChartCaptureBoundary(
                        captureKey: DashboardChartKeys.priceTrend,
                        child: AdminPriceTrendCard(
                          commodities: commodities,
                          baselineByCommodity: baselineByCommodity,
                          weeklyPricesByCommodity: weeklyPricesByCommodity,
                        ),
                      ),
                      AdminTopProductsCard(products: topProducts),
                    ],
                    flexes: const [3, 2],
                  ),

                  const SizedBox(height: 16),

                  // ---- 4. MARKET TRENDS ---- (the card is titled)
                  const AdminMarketTrendsCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // The Overview strip. Each figure is on its own: a shimmer while it
  // loads, the number once it has, or a dash with "could not load" if only
  // that one failed — the other three are unaffected either way.
  Widget _overviewStrip(DashboardOverviewService metrics) {
    AdminOverviewItem item<T>(
      OverviewMetric<T> metric, {
      required String label,
      required IconData icon,
      required String Function(T value) value,
      required String Function(T value) caption,
      VoidCallback? onTap,
      bool attention = false,
    }) {
      if (metric.isLoading) {
        return AdminOverviewItem(
          label: label,
          icon: icon,
          value: null,
          caption: '',
          attention: attention,
          onTap: onTap,
        );
      }
      if (metric.hasError) {
        return AdminOverviewItem(
          label: label,
          icon: icon,
          value: '—',
          caption: 'Could not load · reload the page',
          failed: true,
          attention: attention,
          onTap: onTap,
        );
      }
      final data = metric.value as T;
      return AdminOverviewItem(
        label: label,
        icon: icon,
        value: value(data),
        caption: caption(data),
        attention: attention,
        onTap: onTap,
      );
    }

    // Each card opens the page its figure comes from — except Total
    // Transaction Value, which has no page of its own.
    void open(AdminNotificationTarget page) =>
        adminOpenPageRequest.value = page;

    return AdminOverviewStrip(
      items: [
        // Marketplace users only: buyers plus APPROVED farmers. Pending and
        // rejected farmer applications, and Admin accounts, are not counted.
        item(
          metrics.totalUsers,
          label: 'Total Users',
          icon: Icons.groups_2_outlined,
          value: (v) => '${v.farmers + v.buyers}',
          caption: (v) =>
              '${v.farmers} approved ${v.farmers == 1 ? 'farmer' : 'farmers'}'
              ' · ${v.buyers} ${v.buyers == 1 ? 'buyer' : 'buyers'}',
          onTap: () {
            AdminSubNav.accounts.value = UserAccountsSection.farmers;
            open(AdminNotificationTarget.farmers);
          },
        ),
        // Farmers who registered and are neither approved nor rejected yet.
        item(
          metrics.pendingVerifications,
          label: 'Pending Verifications',
          icon: Icons.fact_check_outlined,
          value: (v) => '$v',
          caption: (_) => 'Farmers awaiting admin review',
          attention: true,
          onTap: () => open(AdminNotificationTarget.verification),
        ),
        // Reports not yet resolved or dismissed, whoever filed them.
        item(
          metrics.flaggedReports,
          label: 'Flagged Reports',
          icon: Icons.flag_outlined,
          value: (v) => '$v',
          caption: (_) => 'Active, unresolved cases',
          onTap: () {
            AdminSubNav.moderation.value = ModerationSection.pending;
            open(AdminNotificationTarget.moderation);
          },
        ),
        // Sum of completed orders only — never pending, cancelled or
        // rejected ones.
        item(
          metrics.totalTransactionValue,
          label: 'Total Transaction Value',
          icon: Icons.payments_outlined,
          value: (v) => formatPeso(v),
          caption: (_) => 'Completed orders only',
        ),
      ],
    );
  }
}

/// The dashboard's two chart sections before their data is in: the
/// headings and one skeleton per card, laid out exactly like the real
/// sections so the page is in place at once.
class _DashboardSectionsSkeleton extends StatelessWidget {
  const _DashboardSectionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Sales Performance'),
        const SizedBox(height: 12),
        _responsiveRow(
          const [AdminChartCardSkeleton(), AdminChartCardSkeleton()],
          flexes: const [3, 2],
        ),
        const SizedBox(height: 16),
        _responsiveRow(
          const [
            AdminChartCardSkeleton(bodyHeight: 288),
            AdminChartCardSkeleton(bodyHeight: 288),
          ],
          flexes: const [3, 2],
        ),
      ],
    );
  }
}

/// The User Accounts page: the farmers (the Farmer List), or the buyers'
/// accounts — chosen from the sidebar's submenu (see AdminSubNav.accounts).
/// Both stay alive, so switching back does not reload either.
class _UserAccountsPage extends StatelessWidget {
  const _UserAccountsPage();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserAccountsSection>(
      valueListenable: AdminSubNav.accounts,
      builder: (context, section, _) => IndexedStack(
        index: section.index,
        sizing: StackFit.expand,
        children: [
          const FarmerListView(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The title is in the utility bar above.
                const Expanded(child: AdminUserAccountsView(buyersOnly: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

// ============================================================
// DEMAND HEATMAP — a smooth, blended density layer (ride-hailing-app
// style) instead of separate per-barangay circles.
//
// Completed orders only, for the selected Month/Year, by the BUYER's own
// saved area (see DashboardAnalyticsService._resolveBuyerArea) — never the
// farmer's, product's or seller's. Purchases are counted per area and each
// area is one point, weighted by its count: more completed purchases means
// stronger heat. Aggregated only — no buyer's identity or exact pin is
// plotted. See _buildDemandPoints below.
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

// The heat is drawn by the map itself, as circles at each area (see
// _HeatmapMapState._heatCircles), in the green -> yellow -> orange -> red
// scale of admin_demand_widgets.dart — not with a heatmap layer:
// Google deprecated google.maps.visualization.HeatmapLayer as of Maps
// JavaScript API v3.65 (confirmed live, in this project, on 2026-09-28 —
// the map tile itself rendered Google's own deprecation error banner) —
// google_maps_flutter's Heatmap widget still only targets that removed API
// on web, so it's unusable here now.

// Real completed-order demand only — no mock/baseline padding. One point
// per buyer area (DashboardAnalyticsService.demandByBuyerAreaForMonth),
// at that area's general location, weighted by its number of completed
// purchases — the weight becomes the heat's colour and size. An area
// with no completed purchase has no point, and a buyer with no location on
// file contributes to none, rather than a fabricated one.
// Shown on the map and in Highest Demand Areas when the selected
// Month/Year has no completed purchase with a buyer area.
const String _noDemandMessage = 'No completed buyer purchases for this period.';

List<WeightedLatLng> _buildDemandPoints(
  List<({String area, int orderCount, num revenue, double? lat, double? lng})>
  demand,
) {
  return [
    for (final area in demand)
      // An area still being located has no point yet.
      if (area.orderCount > 0 && area.lat != null && area.lng != null)
        WeightedLatLng(
          LatLng(area.lat!, area.lng!),
          weight: area.orderCount.toDouble(),
        ),
  ];
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
  const pad =
      0.015; // ~1.6km margin so edge barangays aren't flush against the pan limit
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
  // In the browser this limit applies to the whole visible map, not just
  // its centre: with a tight margin the Town view was already wider than
  // the limit, so the map could not be dragged at all. ~28km of room keeps
  // the map around Laurel while leaving it free to move at every preset.
  const pad = 0.25;
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

/// What the Demand Heatmap is showing: where buyers bought, or where they
/// searched. Two layers, never combined.
enum _HeatLayer { purchases, searches }

class _DemandHeatmapView extends StatefulWidget {
  const _DemandHeatmapView();

  @override
  State<_DemandHeatmapView> createState() => _DemandHeatmapViewState();
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _DemandHeatmapViewState extends State<_DemandHeatmapView> {
  static const _center = LatLng(kLaurelCenterLat, kLaurelCenterLng);

  // _usersStream reuses DashboardDataService's shared, app-session-lifetime
  // Stream instance (see dashboard_data_service.dart) instead of opening a
  // second independent 'users' listener — the Analytics Dashboard already
  // subscribes to the same instance. Completed orders / products no longer
  // need their own stream fields at all: DashboardDataService.instance.
  // orders/.products is a cached one-shot fetch shared across every admin
  // page, read directly in build() below via a ListenableBuilder.
  Stream<QuerySnapshot<Map<String, dynamic>>> get _usersStream =>
      DashboardDataService.instance.usersStream;

  // Buyers' map pins (users/{uid}/private/geo — exact coordinates are kept
  // off the main user doc, see firestore.rules). Read once each, only for
  // the buyers behind a completed order, and kept for the session — instead
  // of a live collection-group listener on every `private` document in the
  // database, which also pulled in every order's contact document.
  // null = looked up, no pin saved.
  static final Map<String, ({double lat, double lng})?> _buyerPins = {};
  static final Set<String> _buyerPinsInFlight = {};
  final ValueNotifier<int> _buyerPinsVersion = ValueNotifier<int>(0);

  void _loadBuyerPins(Set<String> buyerIds) {
    final missing = [
      for (final id in buyerIds)
        if (!_buyerPins.containsKey(id) && _buyerPinsInFlight.add(id)) id,
    ];
    if (missing.isEmpty) return;
    final users = FirebaseFirestore.instance.collection('users');
    AdminPerf.time(
      'heatmap: buyer pins',
      () => Future.wait([
        for (final id in missing)
          users
              .doc(id)
              .collection('private')
              .doc('geo')
              .get()
              .then<({double lat, double lng})?>((doc) {
                final lat = (doc.data()?['latitude'] as num?)?.toDouble();
                final lng = (doc.data()?['longitude'] as num?)?.toDouble();
                return lat == null || lng == null ? null : (lat: lat, lng: lng);
              })
              // Unreadable for one buyer: that one has no pin, the rest
              // are unaffected.
              .catchError((Object _) => null),
      ]),
      describe: (pins) =>
          '${pins.length} buyers, ${pins.where((p) => p != null).length} '
          'with a pin',
    ).then((pins) {
      for (var i = 0; i < missing.length; i++) {
        _buyerPinsInFlight.remove(missing[i]);
        _buyerPins[missing[i]] = pins[i];
      }
      if (mounted) _buyerPinsVersion.value++;
    });
  }

  @override
  void initState() {
    super.initState();
    DashboardDataService.instance.ensureLoaded();
    _loadAreaCache();
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _buyerPinsVersion.dispose();
    super.dispose();
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
  CameraPosition _camera = const CameraPosition(
    target: _center,
    zoom: _zoomStreetLevel,
  );

  // Which month/year the camera was last auto-framed for — null on first
  // build so even the very first render frames on real data if there is
  // any, not just Laurel's fixed center. Deliberately NOT reset by every
  // Firestore snapshot update (only by an actual Month/Year change, below
  // in build()) so the admin's own manual panning within one selection is
  // never yanked back.
  int? _framedMonth;
  int? _framedYear;

  // The area whose purchases Most Purchased Products by Area shows. Chosen
  // from Highest Demand Areas or by clicking its heat on the map; until
  // then (and whenever a period no longer has it) the busiest area.
  String? _selectedArea;

  // Goes up each time the Admin picks an area, so the map moves to it —
  // even when the same area is picked again after panning away.
  int _focusRequest = 0;

  void _selectArea(String area) => setState(() {
    _selectedArea = area;
    _focusRequest++;
  });

  // Which demand the map shows. Purchases and searches are two separate
  // layers: switching replaces one with the other, it never blends them.
  _HeatLayer _layer = _HeatLayer.purchases;

  // Buyer searches for the selected month — a live listener on just that
  // month's records, opened only while the Searches layer is shown.
  // null = not loaded yet.
  List<Map<String, dynamic>>? _searchEvents;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _searchSubscription;
  int? _searchPeriod;

  void _watchSearches() {
    final period = _selectedYear * 12 + _selectedMonth;
    if (_searchPeriod == period && _searchSubscription != null) return;
    _searchSubscription?.cancel();
    _searchPeriod = period;
    _searchEvents = null;
    final window = DashboardAnalyticsService.monthWindow(
      _selectedYear,
      _selectedMonth,
    );
    _searchSubscription =
        AdminPerf.firstEvent(
          'heatmap: searchEvents for the month (live)',
          FirebaseFirestore.instance
              .collection('searchEvents')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(window.start),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(window.end))
              .snapshots(),
          describe: (s) => '${s.docs.length} docs',
        ).listen(
          (snapshot) {
            if (!mounted || _searchPeriod != period) return;
            setState(() {
              _searchEvents = [for (final doc in snapshot.docs) doc.data()];
            });
          },
          onError: (Object _) {
            if (!mounted || _searchPeriod != period) return;
            // Shown as "no searches" rather than loading forever; switching
            // month or layer tries again.
            _searchSubscription = null;
            setState(() => _searchEvents = const []);
          },
        );
  }

  // Where an area is, for the ones no buyer pin could place: looked up
  // once by name and kept for the session. null = looked up, not found.
  static final Map<String, ({double lat, double lng})?> _areaLookups = {};
  static final Set<String> _areaLookupsInFlight = {};

  Map<String, ({double lat, double lng})> get _areaCoordinates => {
    for (final entry in _areaLookups.entries)
      if (entry.value != null) entry.key: entry.value!,
  };

  // The lookups run one after another, a little over a second apart: the
  // public lookup service allows one request per second.
  static Future<void> _areaLookupQueue = Future.value();

  // Area name → where it is, kept in this browser's storage. Place names
  // and their public coordinates only — nothing about any buyer. Areas
  // that could not be found are not kept, so they are tried again later.
  static const String _areaCacheKey = 'admin_area_coordinates_v1';
  static bool _areaCacheLoaded = false;

  Future<void> _loadAreaCache() async {
    if (_areaCacheLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_areaCacheKey);
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final at = entry.value;
            if (at is List && at.length == 2 && at[0] is num && at[1] is num) {
              _areaLookups.putIfAbsent(
                entry.key.toString(),
                () => (
                  lat: (at[0] as num).toDouble(),
                  lng: (at[1] as num).toDouble(),
                ),
              );
            }
          }
        }
      }
    } catch (_) {
      // Storage unavailable or unreadable: the areas are simply looked up.
    }
    _areaCacheLoaded = true;
    if (mounted) setState(() {});
  }

  static Future<void> _saveAreaCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _areaCacheKey,
        jsonEncode({
          for (final entry in _areaLookups.entries)
            if (entry.value != null)
              entry.key: [entry.value!.lat, entry.value!.lng],
        }),
      );
    } catch (_) {
      // Not saved: they are looked up again next time.
    }
  }

  // Fire-and-forget, safe on every rebuild: each area is asked for once.
  // An area is a barangay or town, so this locates a place — it is not a
  // buyer's address — so it is used as found: rounding it, as buyers'
  // own pins are rounded, would only move the area off its real spot.
  //
  // What is found is remembered on this browser (see _loadAreaCache), so
  // an area is looked up once, not once every time the portal is opened.
  void _locateAreas(List<String> areas) {
    // Not before the remembered coordinates are in: they may already hold
    // these areas.
    if (!_areaCacheLoaded) return;
    for (final area in areas) {
      if (_areaLookups.containsKey(area) || !_areaLookupsInFlight.add(area)) {
        continue;
      }
      _areaLookupQueue = _areaLookupQueue.then((_) async {
        final found = await GeocodingService.forwardGeocode(
          '$area, Philippines',
        );
        _areaLookupsInFlight.remove(area);
        _areaLookups[area] = found == null
            ? null
            : (lat: found.lat, lng: found.lng);
        if (found != null) _saveAreaCache();
        // Found or not, the map has something new to say.
        if (mounted) setState(() {});
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
    }
  }

  void _onCameraIdle(CameraPosition position) {
    _camera = position;
  }

  Future<void> _openFullscreen(
    BuildContext context, {
    required List<WeightedLatLng> points,
    required LatLngBounds bounds,
    required VoidCallback onExport,
    String? emptyMessage,
    String legendTitle = 'Completed purchases',
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
            child: _FullscreenHeatmapPage(
              initialCamera: _camera,
              points: points,
              bounds: bounds,
              onCameraIdle: _onCameraIdle,
              onExport: onExport,
              emptyMessage: emptyMessage,
              legendTitle: legendTitle,
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
    List<({String area, int orderCount, num revenue, double? lat, double? lng})>
    demand,
  ) async {
    final periodLabel = '${_monthNames[_selectedMonth - 1]} $_selectedYear';
    // Buyer searches are only part of the exported report, so they are read
    // once, here, when a report is asked for — not kept open as a live
    // listener for the whole time the page is on screen.
    var topSearches = const <MapEntry<String, int>>[];
    try {
      final searches = await AdminPerf.time(
        'heatmap export: searchEvents',
        // Only the month being exported — not the whole collection.
        () {
          final window = DashboardAnalyticsService.monthWindow(
            _selectedYear,
            _selectedMonth,
          );
          return FirebaseFirestore.instance
              .collection('searchEvents')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(window.start),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(window.end))
              .get();
        },
        describe: (s) => '${s.docs.length} docs',
      );
      topSearches = DashboardAnalyticsService.topSearchQueriesForMonth(
        searches.docs,
        year: _selectedYear,
        month: _selectedMonth,
      );
    } catch (_) {
      // The report is still exported, without the searches table's rows.
    }
    final bytes = await PdfReportService.buildDemandReport(
      demand: demand
          .map(
            (d) => (
              barangay: d.area,
              orderCount: d.orderCount,
              revenue: d.revenue,
            ),
          )
          .toList(),
      topSearches: topSearches,
      periodLabel: periodLabel,
    );
    if (!context.mounted) return;
    await PdfReportService.share(bytes, 'agritrade_demand_report.pdf');
    AuditLogService.log(
      AuditAction.exportReport,
      'Exported the Demand Heatmap report ($periodLabel, PDF).',
    );
  }

  // Which product category the heat is for; null = every category.
  String? _category;

  Widget _categorySelector(AdminPalette c) {
    final categories = <String>{
      ...DashboardAnalyticsService.salesCategories,
      ...CommodityRegistry.instance.categories,
    }.toList();
    return Tooltip(
      message: 'Show demand for one product category',
      child: AdminPillDropdown<String?>(
        value: categories.contains(_category) ? _category : null,
        width: 190,
        icon: Icons.category_outlined,
        items: [
          const DropdownMenuItem(value: null, child: Text('All Categories')),
          for (final name in categories)
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: (value) => setState(() => _category = value),
      ),
    );
  }

  // The period is always a whole month: one pill that opens a calendar of
  // months, over the years there is something to show for.
  Widget _monthYearSelector(AdminPalette c, List<int> years) {
    var firstYear = _selectedYear;
    var lastYear = _selectedYear;
    for (final year in years) {
      if (year < firstYear) firstYear = year;
      if (year > lastYear) lastYear = year;
    }
    return AdminMonthPill(
      year: _selectedYear,
      month: _selectedMonth,
      firstYear: firstYear,
      lastYear: lastYear,
      onChanged: (year, month) => setState(() {
        _selectedYear = year;
        _selectedMonth = month;
      }),
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
            // Rebuilt when buyers' map pins arrive (see _loadBuyerPins): the
            // page is drawn first from the areas buyers saved by name, and
            // the pins then place them more exactly.
            return ValueListenableBuilder<int>(
              valueListenable: _buyerPinsVersion,
              builder: (context, _, _) {
                return Builder(
                  builder: (context) {
                    // Only completed orders and user profiles are needed
                    // here — not the product or price lists.
                    if (usersSnap.hasError ||
                        (!svc.ordersReady && svc.lastError != null)) {
                      final failedSource = usersSnap.hasError
                          ? 'user profiles'
                          : 'completed orders';
                      final streamError = usersSnap.error ?? svc.lastError;
                      debugPrint(
                        'Demand Heatmap failed to load $failedSource: $streamError',
                      );
                      return AdminStreamError(
                        source: failedSource,
                        error: streamError,
                      );
                    }
                    if (!usersSnap.hasData || !svc.ordersReady) {
                      return const AdminLoadingSpinner();
                    }

                    final usersByUid = <String, Map<String, dynamic>>{
                      for (final doc in usersSnap.data!.docs)
                        doc.id: doc.data(),
                    };
                    // Pins for the buyers behind a completed order: asked
                    // for once each (a no-op afterwards), merged in as they
                    // are known.
                    _loadBuyerPins({
                      for (final doc in svc.orders)
                        if (usersByUid.containsKey(
                          (doc.data()['buyerId'] ?? '').toString(),
                        ))
                          (doc.data()['buyerId'] ?? '').toString(),
                    });
                    for (final entry in _buyerPins.entries) {
                      final user = usersByUid[entry.key];
                      final pin = entry.value;
                      if (user == null || pin == null) continue;
                      user['latitude'] = pin.lat;
                      user['longitude'] = pin.lng;
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
                      if (lat == null ||
                          lng == null ||
                          isWithinLaurel(lat, lng)) {
                        continue;
                      }
                      final alreadyResolved =
                          (buyer['barangay'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty ||
                          (buyer['municipality'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty ||
                          (buyer['province'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty;
                      GeocodingService.resolveAndCacheIfNeeded(
                        uid: buyerId,
                        lat: lat,
                        lng: lng,
                        alreadyResolved: alreadyResolved,
                      );
                    }

                    final years =
                        DashboardAnalyticsService.yearsWithCompletedOrders(
                          svc.orders,
                          _now,
                        );
                    // One product category at a time, when one is chosen:
                    // by each order's own recorded category, and each
                    // search by the commodity it names.
                    final category = _category;
                    final productById = category == null
                        ? const <String, Map<String, dynamic>>{}
                        : {for (final p in svc.products) p.id: p.data()};
                    final heatOrders = category == null
                        ? svc.orders
                        : [
                            for (final doc in svc.orders)
                              if (DashboardAnalyticsService.orderCategory(
                                    doc.data(),
                                    productById[(doc.data()['productId'] ?? '')
                                        .toString()],
                                  ) ==
                                  category)
                                doc,
                          ];
                    final purchaseDemand =
                        DashboardAnalyticsService.demandByBuyerAreaForMonth(
                          heatOrders,
                          usersByUid,
                          year: _selectedYear,
                          month: _selectedMonth,
                          areaCoordinates: _areaCoordinates,
                        );
                    // The Searches layer: where buyers are looking, counted
                    // the same way but kept entirely apart — searches never
                    // add to purchase heat. Only loaded while it is shown.
                    final showSearches = _layer == _HeatLayer.searches;
                    if (showSearches) _watchSearches();
                    final searches = showSearches
                        ? DashboardAnalyticsService.searchesByBuyerAreaForMonth(
                            category == null
                                ? (_searchEvents ?? const [])
                                : [
                                    for (final event
                                        in _searchEvents ?? const [])
                                      if (categoryOfCommodity(
                                            matchSupportedCommodity(
                                                  (event['query'] ?? '')
                                                      .toString(),
                                                ) ??
                                                '',
                                          ) ==
                                          category)
                                        event,
                                  ],
                            usersByUid,
                            year: _selectedYear,
                            month: _selectedMonth,
                            areaCoordinates: _areaCoordinates,
                          )
                        : null;
                    // One list drives the map and the areas panel, for
                    // whichever layer is shown.
                    final List<
                      ({
                        String area,
                        int orderCount,
                        num revenue,
                        double? lat,
                        double? lng,
                      })
                    >
                    rankedDemand = searches == null
                        ? purchaseDemand
                        : [
                            for (final area in searches.areas)
                              (
                                area: area.area,
                                orderCount: area.searches,
                                revenue: 0,
                                lat: area.lat,
                                lng: area.lng,
                              ),
                          ];
                    final noneMessage = !showSearches
                        ? _noDemandMessage
                        : _searchEvents == null
                        ? 'Loading buyer searches…'
                        : 'No buyer searches for this period.';
                    final areasTitle = showSearches
                        ? 'Top Search Areas'
                        : 'Highest Demand Areas';
                    _locateAreas([
                      for (final area in rankedDemand)
                        if (area.lat == null) area.area,
                    ]);
                    final productsByArea =
                        DashboardAnalyticsService.productsByBuyerAreaForMonth(
                          heatOrders,
                          usersByUid,
                          year: _selectedYear,
                          month: _selectedMonth,
                        );
                    final selectedArea =
                        rankedDemand.any((d) => d.area == _selectedArea)
                        ? _selectedArea
                        : (rankedDemand.isEmpty
                              ? null
                              : rankedDemand.first.area);
                    final plottedAreas = [
                      for (final area in rankedDemand)
                        if (area.lat != null && area.lng != null)
                          (area: area.area, lat: area.lat!, lng: area.lng!),
                    ];
                    // Where the demand is, for framing the map: the areas
                    // themselves, never individual buyers.
                    final buyerPoints = [
                      for (final area in rankedDemand)
                        if (area.lat != null && area.lng != null)
                          (lat: area.lat!, lng: area.lng!),
                    ];
                    // The Month/Year selection just changed (or this is the
                    // first build) — snap the camera to where this period's
                    // real buyer demand actually is instead of leaving it
                    // wherever a previous period's data happened to be (or a
                    // fixed Laurel-only default), so a period with demand
                    // entirely outside Laurel is visible without the admin
                    // having to hunt for it by panning.
                    if (_framedMonth != _selectedMonth ||
                        _framedYear != _selectedYear) {
                      _camera = CameraPosition(
                        // At street level the middle of several areas can
                        // be empty ground, so open on the area with the
                        // most demand (the first; the list is ranked).
                        target: buyerPoints.isEmpty
                            ? _center
                            : LatLng(
                                buyerPoints.first.lat,
                                buyerPoints.first.lng,
                              ),
                        zoom: _zoomStreetLevel,
                      );
                      _framedMonth = _selectedMonth;
                      _framedYear = _selectedYear;
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The title is in the utility bar above.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  _categorySelector(c),
                                  const SizedBox(width: 12),
                                  _monthYearSelector(c, years),
                                  const SizedBox(width: 12),
                                  AdminQuickActionButton(
                                    icon: Icons.download,
                                    label: 'Export Report',
                                    onPressed: () =>
                                        _exportReport(context, purchaseDemand),
                                  ),
                                ],
                              ),
                            ],
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
                                      // Nothing bought, or bought but the
                                      // areas are still being located.
                                      final emptyMessage = rankedDemand.isEmpty
                                          ? noneMessage
                                          : buyerPoints.isNotEmpty
                                          ? null
                                          : rankedDemand.any(
                                              (d) => !_areaLookups.containsKey(
                                                d.area,
                                              ),
                                            )
                                          ? 'Locating buyer areas on the map…'
                                          : 'These buyer areas could not be '
                                                'placed on the map. They are '
                                                'listed under $areasTitle.';
                                      final points = _buildDemandPoints(
                                        rankedDemand,
                                      );
                                      return _HeatmapMap(
                                        initialCamera: _camera,
                                        points: points,
                                        bounds: _computeMapBounds(buyerPoints),
                                        onCameraIdle: _onCameraIdle,
                                        isFullscreen: false,
                                        legendTitle: showSearches
                                            ? 'Buyer searches'
                                            : 'Completed purchases',
                                        emptyMessage: emptyMessage,
                                        areas: plottedAreas,
                                        onSelectArea: _selectArea,
                                        focusArea: _selectedArea,
                                        focusRequest: _focusRequest,
                                        onToggleFullscreen: () =>
                                            _openFullscreen(
                                              context,
                                              emptyMessage: emptyMessage,
                                              legendTitle: showSearches
                                                  ? 'Buyer searches'
                                                  : 'Completed purchases',
                                              points: points,
                                              bounds: _computeMapBounds(
                                                buyerPoints,
                                              ),
                                              onExport: () => _exportReport(
                                                context,
                                                purchaseDemand,
                                              ),
                                            ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        // Where buyers purchased, or where
                                        // they searched: tabs on the panel
                                        // they change. No counts: these
                                        // are two views, not two lists.
                                        child: AdminTabbedTable<_HeatLayer>(
                                          expand: true,
                                          selected: _layer,
                                          onSelected: (layer) =>
                                              setState(() => _layer = layer),
                                          tabs: const [
                                            (
                                              value: _HeatLayer.purchases,
                                              label: 'Purchases',
                                              count: null,
                                              icon: Icons.shopping_bag_outlined,
                                            ),
                                            (
                                              value: _HeatLayer.searches,
                                              label: 'Searches',
                                              count: null,
                                              icon: Icons.search_rounded,
                                            ),
                                          ],
                                          child: AdminDemandAreasPanel(
                                            tabbed: true,
                                            areas: [
                                              for (final d in rankedDemand)
                                                if (d.orderCount > 0)
                                                  (
                                                    area: d.area,
                                                    orderCount: d.orderCount,
                                                  ),
                                            ],
                                            selectedArea: selectedArea,
                                            onSelect: _selectArea,
                                            emptyText: noneMessage,
                                            title: areasTitle,
                                            subtitle: showSearches
                                                ? 'By buyer searches · select an area'
                                                : 'By completed buyer purchases · select an area',
                                            unit: showSearches
                                                ? 'search'
                                                : 'purchase',
                                            unitPlural: showSearches
                                                ? 'searches'
                                                : 'purchases',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: searches != null
                                            ? AdminAreaSearchesPanel(
                                                area: selectedArea,
                                                terms:
                                                    searches
                                                        .terms[selectedArea] ??
                                                    const [],
                                                emptyText: noneMessage,
                                              )
                                            : AdminAreaProductsPanel(
                                                area: selectedArea,
                                                products:
                                                    productsByArea[selectedArea] ??
                                                    const [],
                                                emptyText: noneMessage,
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

  /// Shown over the map when there is nothing to plot; null for none.
  final String? emptyMessage;

  /// What the heat counts, for the legend.
  final String legendTitle;

  /// The areas behind the heat, so a click on the map can select one.
  final List<({String area, double lat, double lng})> areas;
  final ValueChanged<String>? onSelectArea;

  /// The area the Admin picked; the map moves to it each time
  /// [focusRequest] changes.
  final String? focusArea;
  final int focusRequest;
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
    this.areas = const [],
    this.onSelectArea,
    this.focusArea,
    this.focusRequest = 0,
    required this.isFullscreen,
    this.emptyMessage,
    this.legendTitle = 'Completed purchases',
    required this.onToggleFullscreen,
    this.onExport,
  });

  @override
  State<_HeatmapMap> createState() => _HeatmapMapState();
}

class _HeatmapMapState extends State<_HeatmapMap> {
  GoogleMapController? _controller;

  // The last camera the map reported, handed back to the page so the view
  // carries over into and out of full screen.
  late CameraPosition _lastCamera = widget.initialCamera;

  final GlobalKey _mapKey = GlobalKey();
  void Function()? _stopTrackpadPan;

  @override
  void initState() {
    super.initState();
    _stopTrackpadPan = listenTrackpadPan(_panByTrackpad);
  }

  @override
  void dispose() {
    _stopTrackpadPan?.call();
    super.dispose();
  }

  @override
  void didUpdateWidget(_HeatmapMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequest != oldWidget.focusRequest) _showFocusArea();
  }

  // Moves the map to the area the Admin picked, at street level — never
  // zooming out if the map is already closer than that.
  void _showFocusArea() {
    for (final area in widget.areas) {
      if (area.area != widget.focusArea) continue;
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(area.lat, area.lng),
          _lastCamera.zoom < _zoomStreetLevel
              ? _zoomStreetLevel
              : _lastCamera.zoom,
        ),
      );
      return;
    }
  }

  // A laptop trackpad's two-finger scroll over the map moves it, the way
  // dragging does. (On its own the map would zoom instead.) Pinch and the
  // mouse wheel still zoom — see listenTrackpadPan.
  bool _panByTrackpad(double x, double y, double dx, double dy) {
    final controller = _controller;
    if (!mounted || controller == null) return false;
    // Only when the pointer is really on this map: not while the page is
    // kept in the background behind another one (its place on screen is
    // still there), and not through a dialog, menu or full screen over it.
    // Anywhere else the scroll is left alone, so pages scroll as usual.
    final box = _mapKey.currentContext?.findRenderObject();
    if (box == null) return false;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      Offset(x, y),
      View.of(context).viewId,
    );
    if (!hit.path.any((entry) => entry.target == box)) return false;
    controller.moveCamera(CameraUpdate.scrollBy(dx, dy));
    return true;
  }

  // ---- The heat ----
  // Each area is drawn by the map itself, as circles anchored to the
  // area's real coordinates — so the colour is in the right place from the
  // moment the map appears and stays there through every pan and zoom,
  // with nothing in the app to keep in step. (It used to be painted over
  // the map from the app's idea of the camera, which could be out of date
  // until the map was next moved.)
  //
  // An area is three circles of the same colour, widest and faintest
  // first, so it fades outward like heat rather than ending in a hard
  // edge. Their size is in metres — an area's worth of ground — so the
  // spot grows as the map zooms in on it.
  static const List<({double size, double opacity})> _heatRings = [
    (size: 1.00, opacity: 0.16),
    (size: 0.68, opacity: 0.22),
    (size: 0.38, opacity: 0.30),
  ];
  static const double _heatRadiusMetres = 900;
  static const double _heatRadiusBoostMetres = 600;

  Set<Circle> _heatCircles() {
    if (widget.points.isEmpty) return const {};
    final busiest = widget.points
        .map((p) => p.weight)
        .reduce((a, b) => a > b ? a : b);
    // Lowest demand first, so the busiest area is drawn on top.
    final ordered = [...widget.points]
      ..sort((a, b) => a.weight.compareTo(b.weight));
    final circles = <Circle>{};
    for (var i = 0; i < ordered.length; i++) {
      final point = ordered[i];
      // Against the busiest area, never below the scale's floor.
      final intensity = demandIntensity(point.weight, busiest);
      final color = heatColorForIntensity(intensity);
      final radius = _heatRadiusMetres + _heatRadiusBoostMetres * intensity;
      final area = _areaAt(point.point);
      for (var ring = 0; ring < _heatRings.length; ring++) {
        circles.add(
          Circle(
            circleId: CircleId('heat-$i-$ring'),
            center: point.point,
            radius: radius * _heatRings[ring].size,
            fillColor: color.withValues(alpha: _heatRings[ring].opacity),
            strokeWidth: 0,
            zIndex: i,
            // A click on an area's heat selects that area.
            consumeTapEvents: area != null && widget.onSelectArea != null,
            onTap: area == null ? null : () => widget.onSelectArea?.call(area),
          ),
        );
      }
    }
    return circles;
  }

  // The area a heat point belongs to.
  String? _areaAt(LatLng point) {
    for (final area in widget.areas) {
      if (area.lat == point.latitude && area.lng == point.longitude) {
        return area.area;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: _mapKey,
      borderRadius: widget.isFullscreen
          ? BorderRadius.zero
          : BorderRadius.circular(16),
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
              // normally — never disabled.
              zoomGesturesEnabled: true,
              // Rotate/tilt stay off: neither was asked for; only pan and
              // zoom are.
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              // Keeps the map to wherever the real data actually is —
              // Laurel itself, plus any buyer point outside it (see
              // _computeMapBounds) — instead of a fixed Laurel-only lock,
              // since buyers aren't geo-restricted the way farmers are.
              cameraTargetBounds: CameraTargetBounds(widget.bounds),
              minMaxZoomPreference: const MinMaxZoomPreference(
                6,
                _zoomStreetLevel + 1,
              ),
              // The demand itself: see _heatCircles.
              circles: _heatCircles(),
              onMapCreated: (controller) => _controller = controller,
              onCameraMove: (position) => _lastCamera = position,
              onCameraIdle: () => widget.onCameraIdle(_lastCamera),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                if (widget.isFullscreen && widget.onExport != null) ...[
                  _MapIconButton(
                    icon: Icons.download,
                    tooltip: 'Export Report',
                    onPressed: widget.onExport!,
                  ),
                  const SizedBox(height: 8),
                ],
                _MapIconButton(
                  icon: widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  tooltip: widget.isFullscreen
                      ? 'Exit full screen'
                      : 'Full screen',
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
                  onPressed: () => _controller?.animateCamera(
                    CameraUpdate.zoomTo(_zoomTownLevel),
                  ),
                ),
                const SizedBox(height: 4),
                _MapIconButton(
                  icon: Icons.center_focus_weak,
                  tooltip: 'Barangay view',
                  onPressed: () => _controller?.animateCamera(
                    CameraUpdate.zoomTo(_zoomBarangayLevel),
                  ),
                ),
                const SizedBox(height: 4),
                _MapIconButton(
                  icon: Icons.zoom_in_map,
                  tooltip: 'Street view',
                  onPressed: () => _controller?.animateCamera(
                    CameraUpdate.zoomTo(_zoomStreetLevel),
                  ),
                ),
              ],
            ),
          ),
          // Nothing to plot: say so on the map itself, not just beside it.
          if (widget.emptyMessage != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AdminRadii.pill),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.emptyMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: AdminHeatLegend(title: widget.legendTitle),
          ),
        ],
      ),
    );
  }
}

/// Small circular button matching Google Maps' own native control style
/// (always white/black regardless of the admin dashboard's dark/light
/// theme) — it sits on top of the map itself, not the surrounding page.
class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _MapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

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
  final String? emptyMessage;

  /// What the heat counts, for the legend.
  final String legendTitle;

  const _FullscreenHeatmapPage({
    required this.initialCamera,
    required this.points,
    required this.bounds,
    required this.onCameraIdle,
    required this.onExport,
    this.emptyMessage,
    this.legendTitle = 'Completed purchases',
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
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
                emptyMessage: emptyMessage,
                legendTitle: legendTitle,
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

/// Keeps one dated entry per reference price under
/// `market_prices/{commodity}/history`, so the office's prices build into
/// a month-by-month record instead of each new one replacing the last.
/// The entry is keyed by its date: saving a price for a date that already
/// has one corrects it rather than adding a second.
void _recordReferencePrice(
  WriteBatch batch,
  DocumentReference<Map<String, dynamic>> commodity, {
  required double price,
  required String unit,
  required DateTime effectiveDate,
  required String updatedBy,
}) {
  final day = DateUtils.dateOnly(effectiveDate);
  batch.set(
    commodity.collection('history').doc(DateFormat('yyyy-MM-dd').format(day)),
    {
      'price': price,
      'unit': unit,
      'effectiveDate': Timestamp.fromDate(day),
      'year': day.year,
      'month': day.month,
      'recordedAt': FieldValue.serverTimestamp(),
      'recordedBy': updatedBy,
    },
  );
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
    rows.add(
      line
          .split(',')
          .map((cell) => _Cell(cell.trim().replaceAll(RegExp(r'^"|"$'), '')))
          .toList(),
    );
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

String _normalizeHeader(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Map<String, int> _headerIndex(List<_Cell> headerRow) {
  final index = <String, int>{};
  for (var i = 0; i < headerRow.length; i++) {
    final norm = _normalizeHeader(headerRow[i].text);
    if (norm.isNotEmpty) index.putIfAbsent(norm, () => i);
  }
  return index;
}

int? _resolveColumn(
  Map<String, int> normalizedHeaderIndex,
  List<String> aliases,
) {
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
  for (final pattern in [
    'M/d/yyyy',
    'MM/dd/yyyy',
    'yyyy/MM/dd',
    'MMM d, yyyy',
    'MMMM d, yyyy',
    'd MMM yyyy',
    'MM-dd-yyyy',
  ]) {
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
    return const _PriceImportParseResult(
      headerError: 'This file appears to be empty.',
    );
  }

  final index = _headerIndex(rawRows.first);
  final nameCol = _resolveColumn(index, const [
    'commodityname',
    'commodity',
    'name',
    'productname',
    'product',
  ]);
  final priceCol = _resolveColumn(index, const [
    'referenceprice',
    'baselineprice',
    'price',
  ]);
  final dateCol = _resolveColumn(index, const ['effectivedate', 'date']);

  final missing = <String>[];
  if (nameCol == null) missing.add('CommodityName');
  if (priceCol == null) missing.add('ReferencePrice');
  if (dateCol == null) missing.add('EffectiveDate');
  if (missing.isNotEmpty) {
    return _PriceImportParseResult(
      headerError:
          'This file is missing required column(s): ${missing.join(', ')}. Expected headers: '
          'CommodityID, Category, CommodityName, Unit, ReferencePrice, MinimumPrice, MaximumPrice, '
          'EffectiveDate, Source, IsTestData (CommodityName, ReferencePrice, and EffectiveDate are required).',
    );
  }

  final unitCol = _resolveColumn(index, const ['unit']);
  final minCol = _resolveColumn(index, const ['minimumprice', 'minprice']);
  final maxCol = _resolveColumn(index, const ['maximumprice', 'maxprice']);
  final sourceCol = _resolveColumn(index, const ['source']);
  final testCol = _resolveColumn(index, const ['istestdata', 'testdata']);

  _Cell cellAt(List<_Cell> cells, int? col) =>
      (col != null && col < cells.length) ? cells[col] : const _Cell('');

  final results = <_PriceImportRow>[];
  final seenCommodities = <String>{};
  var rowNumber = 1;

  for (final cells in rawRows.skip(1)) {
    rowNumber++;
    if (cells.every((c) => c.isBlank)) {
      continue; // blank rows are skipped, not flagged invalid
    }

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
        error =
            'Duplicate commodity in this file — only the first occurrence is imported';
      }
    }

    results.add(
      _PriceImportRow(
        rowNumber: rowNumber,
        rawName: rawName,
        matchedCommodity: matched,
        category: matched != null ? categoryOfCommodity(matched) : null,
        referencePrice: price,
        effectiveDate: effectiveDate,
        minimumPrice: double.tryParse(
          cellAt(cells, minCol).text.replaceAll(',', ''),
        ),
        maximumPrice: double.tryParse(
          cellAt(cells, maxCol).text.replaceAll(',', ''),
        ),
        unit: unit.isEmpty ? null : unit,
        source: source.isEmpty ? null : source,
        isTestData: const ['true', '1', 'yes'].contains(testText.toLowerCase()),
        error: error,
      ),
    );
  }

  return _PriceImportParseResult(rows: results);
}

class _PriceManagementView extends StatefulWidget {
  const _PriceManagementView();

  @override
  State<_PriceManagementView> createState() => _PriceManagementViewState();
}

class _PriceManagementViewState extends State<_PriceManagementView>
    with AdminPageSearch {
  // Typed in the header's search box. It matches the table's text columns
  // only — Commodity, Category, Status and Unit — not its prices or dates.
  String get _search => pageSearch.trim().toLowerCase();

  // A commodity's Status, as its column shows it.
  static String _statusLabel(
    Map<String, dynamic> data, {
    required String? category,
    required bool isActive,
  }) {
    if (!isActive) {
      final reason = (data['archiveReason'] ?? '').toString().trim();
      return reason.isEmpty ? 'Archived' : 'Archived — $reason';
    }
    return category == null ? 'No category' : 'Active';
  }

  // The commodities whose box is ticked, by document id.
  final Set<String> _ticked = {};
  bool _archiving = false;

  // Which of the page's two tables is open: the commodities in use, or
  // the archive.
  bool _showArchived = false;

  // Each commodity's Current Market Average for the listings last seen.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _averagedProducts;
  final Map<String, double?> _liveAverages = {};

  // Archives commodities, or restores archived ones. Archived is the
  // commodity's existing "not active" state (isActive: false): farmers are
  // not offered it when posting a product (see CommodityRegistry). Nothing
  // is deleted — its reference price and price history stay as they are.
  Future<void> _setArchived(
    BuildContext context,
    Map<String, String> commodities, {
    required bool archived,
  }) async {
    if (commodities.isEmpty || _archiving) return;
    final label = commodities.length > 1
        ? '${commodities.length} commodities'
        : '"${commodities.values.first}"';
    // Archiving stops the commodity's selling for everyone, so it needs
    // its reason: the farmers who sell it are told it.
    final reasonController = TextEditingController();
    var missingReason = false;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(archived ? 'Archive $label?' : 'Restore $label?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  archived
                      ? 'Its selling stops for now: its listings are '
                            'hidden from the marketplace, farmers cannot '
                            'post it, and the farmers who sell it are '
                            'notified with the reason below. Its reference '
                            'price and price history are kept, and it can be '
                            'restored at any time.'
                      : 'Its listings return to the marketplace, farmers '
                            'can post it again, and the farmers who sell it '
                            'are notified that it is available.',
                ),
                if (archived) ...[
                  const SizedBox(height: 14),
                  AdminField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: adminMultilineDecoration(
                      dialogContext,
                      labelText: 'Reason (required)',
                      hintText: 'e.g. Swine flu outbreak in the area',
                    ),
                  ),
                  if (missingReason)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text(
                        'Give the reason: the farmers who sell it will see it.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (archived && reasonController.text.trim().isEmpty) {
                  setDialogState(() => missingReason = true);
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(archived ? 'Archive' : 'Restore'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    if (confirm != true) return;
    if (!await ConnectivityService.instance.checkNow()) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      }
      return;
    }
    if (!context.mounted) return;
    await _writeArchived(
      context,
      commodities,
      archived: archived,
      reason: reason,
    );
  }

  // Archives or restores, then says so in a message at the bottom of the
  // page with an Undo — which puts the same commodities straight back,
  // without asking again.
  Future<void> _writeArchived(
    BuildContext context,
    Map<String, String> commodities, {
    required bool archived,
    bool offerUndo = true,
    // Why it is archived; kept on the commodity, and what farmers and
    // buyers are told (onCommodityArchiveChanged in functions/index.js).
    String reason = '',
  }) async {
    if (_archiving) return;
    final label = commodities.length > 1
        ? '${commodities.length} commodities'
        : '"${commodities.values.first}"';
    setState(() => _archiving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final updatedBy =
          FirebaseAuth.instance.currentUser?.email ??
          FirebaseAuth.instance.currentUser?.uid ??
          'admin';
      final batch = firestore.batch();
      for (final id in commodities.keys) {
        batch.update(firestore.collection('market_prices').doc(id), {
          'isActive': !archived,
          'archiveReason': archived ? reason : FieldValue.delete(),
          'archivedAt': archived
              ? FieldValue.serverTimestamp()
              : FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': updatedBy,
        });
      }
      await batch.commit();
      DashboardDataService.instance.refresh(force: true);
      AuditLogService.log(
        AuditAction.updateBaselinePrice,
        '${archived ? 'Archived' : 'Restored'} '
        '${commodities.values.join(', ')}'
        '${offerUndo ? '' : ' (undo)'}.'
        '${archived && reason.isNotEmpty ? ' Reason: $reason' : ''}',
      );
      if (!context.mounted) return;
      setState(() => _ticked.removeAll(commodities.keys));
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: Duration(seconds: offerUndo ? 8 : 4),
          content: Text(
            archived
                ? 'Archived $label. Find it under Archived.'
                : 'Restored $label.',
          ),
          action: offerUndo
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _writeArchived(
                    this.context,
                    commodities,
                    archived: !archived,
                    offerUndo: false,
                    reason: reason,
                  ),
                )
              : null,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not ${archived ? 'archive' : 'restore'} $label: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _openBaselineDialog(
    BuildContext context, {
    String? commodityId,
    String? name,
    double? price,
    String? unit,
    String? category,
    bool isActive = true,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BaselinePriceDialog(
        commodityId: commodityId,
        initialName: name,
        initialPrice: price,
        initialUnit: unit,
        initialCategory: category,
        initialActive: isActive,
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

  // Not on the page any more (the Import File button was removed); kept
  // so it can be put back without rewriting it.
  // ignore: unused_element
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
          const SnackBar(
            content: Text(
              "Could not read that file — make sure it's a valid .csv or .xlsx file.",
            ),
          ),
        );
      }
      return;
    }

    final parsed = _buildImportRows(rawRows);
    if (parsed.headerError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(parsed.headerError!)));
      }
      return;
    }
    if (parsed.rows.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No rows found in this file — it may only contain a header row.',
            ),
          ),
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
      builder: (_) =>
          _PriceImportPreviewDialog(rows: parsed.rows, fileName: file.name),
    );
    if (confirmed != true) return;

    final validRows = parsed.rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) return;

    if (!context.mounted) return;
    if (!await ConnectivityService.instance.checkNow()) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      }
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final updatedBy =
        FirebaseAuth.instance.currentUser?.email ??
        FirebaseAuth.instance.currentUser?.uid ??
        'admin';
    final batch = firestore.batch();
    final history = firestore.batch();
    for (final row in validRows) {
      // Keyed by the matched, canonical commodity name — never the file's
      // own CommodityID — so an existing commodity is always updated in
      // place instead of creating a duplicate.
      final commodity = row.matchedCommodity!;
      final docId = commodity.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '_',
      );
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
      _recordReferencePrice(
        history,
        docRef,
        price: row.referencePrice!,
        unit: row.unit ?? (existing.data()?['unit'] ?? 'kg').toString(),
        effectiveDate: row.effectiveDate!,
        updatedBy: updatedBy,
      );
    }
    await batch.commit();
    // The dated history is kept on top of the prices themselves: if it
    // cannot be written, the import above still stands.
    try {
      await history.commit();
    } catch (e) {
      debugPrint('[PriceHistory] could not record imported prices: $e');
    }
    DashboardDataService.instance.refresh(force: true);

    final skipped = parsed.rows.length - validRows.length;
    AuditLogService.log(
      AuditAction.importBaselinePrices,
      'Imported ${validRows.length} commodity price(s) from ${file.name}'
      '${skipped > 0 ? ' ($skipped row(s) skipped as invalid)' : ''}.',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${validRows.length} commodity price(s).'),
        ),
      );
    }
  }

  Future<void> _deleteBaseline(
    BuildContext context,
    String commodityId,
    String name,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove admin reference price?'),
        content: Text(
          'This removes the official admin reference price for "$name". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(kNoInternetActionMessage)));
      }
      return;
    }
    await FirebaseFirestore.instance
        .collection('market_prices')
        .doc(commodityId)
        .delete();
    DashboardDataService.instance.refresh(force: true);
    AuditLogService.log(
      AuditAction.deleteBaselinePrice,
      'Removed the admin reference price for "$name".',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    // The top row is above the scrolling page, not in it: Add Commodity
    // and the actions for the ticked rows stay in view, over the table,
    // however far it is scrolled.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _selectionBar(context, c),
              const SizedBox(width: 12),
              // The archive is a page of its own, opened from here: the
              // commodities in use and the archived ones are never listed
              // together.
              ListenableBuilder(
                listenable: DashboardDataService.instance,
                builder: (context, _) {
                  final archivedCount = DashboardDataService
                      .instance
                      .marketPrices
                      .where((doc) => doc.data()['isActive'] == false)
                      .length;
                  return AdminQuickActionButton(
                    icon: _showArchived
                        ? Icons.arrow_back_rounded
                        : Icons.archive_outlined,
                    label: _showArchived
                        ? 'Back to Commodities'
                        : 'Archived ($archivedCount)',
                    onPressed: () => setState(() {
                      _showArchived = !_showArchived;
                      _ticked.clear();
                    }),
                  );
                },
              ),
              const SizedBox(width: 8),
              AdminQuickActionButton(
                icon: Icons.add,
                label: 'Add Commodity',
                filled: true,
                onPressed: () => _openBaselineDialog(context),
              ),
            ],
          ),
        ),
        Expanded(child: _page(context, c)),
      ],
    );
  }

  // "N selected", Clear, and Archive / Restore for the ticked commodities.
  // Nothing while none are ticked.
  Widget _selectionBar(BuildContext context, AdminPalette c) {
    return ListenableBuilder(
      listenable: DashboardDataService.instance,
      builder: (context, _) {
        final tickedActive = <String, String>{};
        final tickedArchived = <String, String>{};
        for (final doc in DashboardDataService.instance.marketPrices) {
          if (!_ticked.contains(doc.id)) continue;
          final data = doc.data();
          (data['isActive'] != false ? tickedActive : tickedArchived)[doc.id] =
              (data['name'] ?? doc.id).toString();
        }
        if (tickedActive.isEmpty && tickedArchived.isEmpty) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminSelectionNote(
              count: tickedActive.length + tickedArchived.length,
              onClear: () => setState(_ticked.clear),
            ),
            // Each button acts on the ticked rows it applies to:
            // Archive on the active, Restore on the archived.
            if (tickedActive.isNotEmpty) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _archiving
                    ? null
                    : () => _setArchived(context, tickedActive, archived: true),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(
                  tickedArchived.isEmpty
                      ? 'Archive selected'
                      : 'Archive (${tickedActive.length})',
                ),
              ),
            ],
            if (tickedArchived.isNotEmpty) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _archiving
                    ? null
                    : () => _setArchived(
                        context,
                        tickedArchived,
                        archived: false,
                      ),
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: Text(
                  tickedActive.isEmpty
                      ? 'Restore selected'
                      : 'Restore (${tickedArchived.length})',
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _page(BuildContext context, AdminPalette c) {
    DashboardDataService.instance.ensureLoaded();
    // The whole page (header/buttons + table) scrolls as one unit — the
    // sidebar and top header outside this widget stay fixed. No nested
    // vertical scroll region for the table itself, so the browser's normal
    // scrollbar reaches every row.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListenableBuilder(
            listenable: DashboardDataService.instance,
            builder: (context, _) {
              final svc = DashboardDataService.instance;
              if (!svc.hasLoadedOnce) {
                return svc.lastError != null
                    ? const AdminStreamError()
                    : const AdminLoadingSpinner();
              }

              final products = svc.products;
              final all = [
                for (final doc in svc.marketPrices)
                  () {
                    final data = doc.data();
                    final name = (data['name'] ?? doc.id).toString();
                    return (
                      id: doc.id,
                      data: data,
                      name: name,
                      category: (data['category'] ?? categoryOfCommodity(name))
                          ?.toString(),
                      // Farmers can post it (Supported Products, Add
                      // Product) only while active and in a category —
                      // see CommodityRegistry. Not active = archived.
                      isActive: data['isActive'] != false,
                    );
                  }(),
              ];
              if (all.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: kAdminTablePadding,
                  decoration: adminTableCard(c),
                  // The header band follows the rounded corners.
                  clipBehavior: Clip.antiAlias,
                  child: const AdminEmptyState(
                    icon: Icons.price_change_outlined,
                    title: 'No admin reference prices set yet',
                    subtitle:
                        'Set official commodity prices to power AI price recommendations.',
                  ),
                );
              }

              // Two tables, never mixed: the commodities in use, and the
              // archive. An archived commodity leaves the first and is
              // found (and restored) in the second.
              final inTable = [
                for (final row in all)
                  if (row.isActive != _showArchived) row,
              ];
              final query = _search;
              final rows = query.isEmpty
                  ? inTable
                  : [
                      for (final row in inTable)
                        if ([
                          row.name,
                          row.category ?? '',
                          _statusLabel(
                            row.data,
                            category: row.category,
                            isActive: row.isActive,
                          ),
                          (row.data['unit'] ?? '').toString(),
                        ].any((text) => text.toLowerCase().contains(query)))
                          row,
                    ];
              final secondary = TextStyle(color: c.textSecondary);

              return Container(
                width: double.infinity,
                padding: kAdminTablePadding,
                decoration: adminTableCard(c),
                // The header band follows the rounded corners.
                clipBehavior: Clip.antiAlias,
                // Sized to fit its content naturally (no fixed/bounded
                // height here) — the page-level scroll above is what
                // reveals rows past the viewport, not a clipped box.
                child: rows.isEmpty && inTable.isNotEmpty
                    ? const AdminEmptyState(
                        icon: Icons.search_off,
                        title: 'No commodities match your search',
                        subtitle:
                            'The search looks at Commodity, Category, Status '
                            'and Unit.',
                      )
                    : rows.isEmpty
                    ? AdminEmptyState(
                        icon: _showArchived
                            ? Icons.archive_outlined
                            : Icons.price_change_outlined,
                        title: _showArchived
                            ? 'No archived commodities'
                            : 'No commodities in use',
                        subtitle: _showArchived
                            ? 'A commodity you archive is kept here, and can be restored.'
                            : 'Add a commodity, or restore one from Archived.',
                      )
                    // 10 commodities a page; back to the first on a new
                    // search or when switching to Archived.
                    : AdminPaged<
                        ({
                          String id,
                          Map<String, dynamic> data,
                          String name,
                          String? category,
                          bool isActive,
                        })
                      >(
                        items: rows,
                        resetKey: (_showArchived, query),
                        builder: (context, page) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AdminTableFit(
                              table: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  adminTableHeaderColor(c),
                                ),
                                dataRowColor: adminTableRowColor(c),
                                columnSpacing: kAdminTableColumnSpacing,
                                horizontalMargin: kAdminTableMargin,
                                headingTextStyle: adminTableHeaderStyle(c),
                                dataTextStyle: TextStyle(
                                  fontFamily: kAdminFontFamily,
                                  color: c.textPrimary,
                                  fontSize: 13,
                                ),
                                columns: const [
                                  DataColumn(label: Text('Commodity')),
                                  DataColumn(label: Text('Category')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(
                                    label: Text(
                                      'Current Market Average (Retail)',
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text('Admin Reference Price'),
                                  ),
                                  DataColumn(label: Text('Unit')),
                                  DataColumn(label: Text('Price Date')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: [
                                  for (final row in page)
                                    _commodityRow(
                                      context,
                                      c,
                                      id: row.id,
                                      data: row.data,
                                      name: row.name,
                                      category: row.category,
                                      isActive: row.isActive,
                                      products: products,
                                      secondary: secondary,
                                    ),
                                ],
                              ),
                            ),
                            // The count; the pager says it on a longer list.
                            if (rows.length <= kAdminRowsPerPage)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        query.isEmpty
                                            ? '${rows.length} '
                                                  '${rows.length == 1 ? 'commodity' : 'commodities'}'
                                            : 'Showing ${rows.length} of '
                                                  '${inTable.length} '
                                                  '${inTable.length == 1 ? 'commodity' : 'commodities'}',
                                        style: TextStyle(
                                          color: c.textSecondary,
                                          fontSize: 12,
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
            },
          ),
        ],
      ),
    );
  }

  DataRow _commodityRow(
    BuildContext context,
    AdminPalette c, {
    required String id,
    required Map<String, dynamic> data,
    required String name,
    required String? category,
    required bool isActive,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    required TextStyle secondary,
  }) {
    final baseline = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
    // Current Market Average comes ONLY from active Farmer listings —
    // never the admin's reference price (see computeLiveAverage). Worked
    // out once per change in the listings: ticking a box or archiving
    // rebuilds the table without going through every listing again.
    if (!identical(_averagedProducts, products)) {
      _averagedProducts = products;
      _liveAverages.clear();
    }
    final liveAverage = _liveAverages.putIfAbsent(
      name,
      () => computeLiveAverage(products, name),
    );
    final unit = (data['unit'] ?? '').toString();
    final effectiveDate = data['effectiveDate'] as Timestamp?;
    return DataRow(
      selected: _ticked.contains(id),
      onSelectChanged: (on) => setState(() {
        if (on ?? false) {
          _ticked.add(id);
        } else {
          _ticked.remove(id);
        }
      }),
      cells: [
        DataCell(Text(name, style: isActive ? null : secondary)),
        DataCell(Text(category ?? '—', style: secondary)),
        DataCell(
          Text(
            _statusLabel(data, category: category, isActive: isActive),
            style: TextStyle(
              color: category != null && isActive
                  ? c.textPrimary
                  : c.textSecondary,
            ),
          ),
        ),
        DataCell(
          Text(
            liveAverage != null
                ? _formatPriceWithUnit(liveAverage, unit)
                : 'No active retail listings',
            style: secondary,
          ),
        ),
        DataCell(
          Text(
            _formatPriceWithUnit(baseline, unit),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(Text(unit.isEmpty ? 'kg' : unit, style: secondary)),
        DataCell(
          Text(
            effectiveDate != null
                ? DateFormat('MMM d, y').format(effectiveDate.toDate())
                : '—',
            style: secondary,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Update reference price',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: c.textSecondary,
                ),
                onPressed: () => _openBaselineDialog(
                  context,
                  commodityId: id,
                  name: name,
                  price: baseline,
                  unit: unit,
                  category: category,
                  isActive: isActive,
                ),
              ),
              // Archive and Restore are on the selection bar above the
              // table: tick the row.
              if (!isActive)
                IconButton(
                  tooltip: 'Remove reference price',
                  icon: Icon(Icons.delete_outline, size: 18, color: c.red),
                  onPressed: () => _deleteBaseline(context, id, name),
                ),
            ],
          ),
        ),
      ],
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validCount = rows.where((r) => r.isValid).length;
    final invalidCount = rows.length - validCount;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: screenHeight * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Import Preview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _summaryChip('Valid rows: $validCount', Colors.green),
                  const SizedBox(width: 8),
                  _summaryChip(
                    'Invalid rows: $invalidCount',
                    invalidCount > 0 ? Colors.red : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: AdminTableFit(
                    table: DataTable(
                      columnSpacing: kAdminTableColumnSpacing,
                      columns: const [
                        DataColumn(label: Text('Commodity')),
                        DataColumn(label: Text('Reference Price')),
                        DataColumn(label: Text('Effective Date')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: rows.map((row) {
                        final statusText = row.isValid
                            ? 'Valid'
                            : row.error ==
                                  'Not a supported AgriTrade+ commodity'
                            ? 'Unsupported'
                            : 'Invalid';
                        final statusCell = Text(
                          statusText,
                          style: TextStyle(
                            color: row.isValid ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                        return DataRow(
                          cells: [
                            DataCell(Text(row.displayName)),
                            DataCell(
                              Text(
                                row.referencePrice != null
                                    ? _formatPriceWithUnit(
                                        row.referencePrice!,
                                        row.unit,
                                      )
                                    : '—',
                              ),
                            ),
                            DataCell(
                              Text(
                                row.effectiveDate != null
                                    ? DateFormat(
                                        'MMM d, y',
                                      ).format(row.effectiveDate!)
                                    : '—',
                              ),
                            ),
                            DataCell(
                              row.isValid
                                  ? statusCell
                                  : Tooltip(
                                      message: row.error!,
                                      child: statusCell,
                                    ),
                            ),
                          ],
                        );
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: validCount > 0
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(
                      validCount > 0
                          ? 'Import Valid Rows ($validCount)'
                          : 'Import Valid Rows',
                    ),
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
  final String? initialCategory;
  final bool initialActive;

  const _BaselinePriceDialog({
    this.commodityId,
    this.initialName,
    this.initialPrice,
    this.initialUnit,
    this.initialCategory,
    this.initialActive = true,
  });

  @override
  State<_BaselinePriceDialog> createState() => _BaselinePriceDialogState();
}

class _BaselinePriceDialogState extends State<_BaselinePriceDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName ?? '',
  );
  late final TextEditingController _priceController = TextEditingController(
    text: widget.initialPrice != null
        ? widget.initialPrice!.toStringAsFixed(2)
        : '',
  );
  // Adding: the unit is typed. Updating: it is chosen from the units the
  // app knows (kCommodityUnitOptions), so a misspelling cannot slip in.
  late final TextEditingController _unitController = TextEditingController(
    text: (widget.initialUnit == null || widget.initialUnit!.isEmpty)
        ? 'kg'
        : widget.initialUnit,
  );
  bool get _editing => widget.commodityId != null;

  /// [text] as one of the known units, ignoring capitals and extra
  /// spaces; null when it is none of them.
  static String? _knownUnit(String? text) {
    final wanted = (text ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    for (final unit in kCommodityUnitOptions) {
      if (unit == wanted) return unit;
    }
    return null;
  }

  // The unit chosen while updating. A saved unit the app does not know
  // (a misspelling) is not offered: one of the known units must be chosen.
  // None saved at all reads as the default unit, as it always has.
  late String? _unitChoice = (widget.initialUnit ?? '').trim().isEmpty
      ? kDefaultUnit
      : _knownUnit(widget.initialUnit);

  Future<void> _chooseUnit(BuildContext plateContext) async {
    final plate = plateContext.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (plate is! RenderBox || overlay is! RenderBox) return;
    final corner = plate.localToGlobal(
      Offset(0, plate.size.height + 4),
      ancestor: overlay,
    );
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        corner.dx,
        corner.dy,
        overlay.size.width - corner.dx - plate.size.width,
        0,
      ),
      constraints: BoxConstraints(
        minWidth: plate.size.width,
        maxWidth: plate.size.width,
      ),
      items: [
        for (final unit in kCommodityUnitOptions)
          PopupMenuItem(
            value: unit,
            child: Text(
              unit,
              style: TextStyle(
                fontWeight: unit == _unitChoice
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
    );
    if (chosen != null && mounted) {
      setState(() {
        _unitChoice = chosen;
        _error = null;
      });
    }
  }

  // The category farmers and buyers see this commodity under, and whether
  // farmers may choose it for a new product. Together with the name and
  // unit these are what Supported Products and Add Product read.
  late final TextEditingController _categoryController = TextEditingController(
    text:
        widget.initialCategory ??
        categoryOfCommodity(widget.initialName ?? '') ??
        '',
  );
  late bool _isActive = widget.initialActive;

  // The date the price being entered applies from: today unless the
  // officer picks an earlier one. Never a future date.
  DateTime _effectiveDate = DateUtils.dateOnly(DateTime.now());

  Future<void> _pickEffectiveDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showAdminDatePicker(
      context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2000),
      lastDate: today,
      title: 'Price date',
    );
    if (picked != null && mounted) setState(() => _effectiveDate = picked);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _products = [];
  bool _loadingProducts = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  // Typing a name already on the list fills in its category.
  void _onNameChanged() {
    if (_categoryController.text.trim().isEmpty) {
      final known = categoryOfCommodity(_nameController.text);
      if (known != null) _categoryController.text = known;
    }
    setState(() {});
  }

  Future<void> _loadProducts() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .get();
      if (mounted) {
        setState(() {
          _products = snap.docs;
          _loadingProducts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    // Typed when adding: a known unit is saved in its own spelling ("KG"
    // → "kg"), anything else as typed.
    final typedUnit = _unitController.text.trim();
    final unit = _editing
        ? (_unitChoice ?? '')
        : (_knownUnit(typedUnit) ?? typedUnit);
    final category = _categoryController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Enter a commodity name.');
      return;
    }
    if (category.isEmpty) {
      setState(() => _error = 'Enter the category this commodity belongs to.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (_editing && _unitChoice == null) {
      setState(() => _error = 'Choose a unit.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    if (!await ConnectivityService.instance.checkNow()) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = kNoInternetActionMessage;
        });
      }
      return;
    }

    try {
      final docId =
          widget.commodityId ??
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final docRef = FirebaseFirestore.instance
          .collection('market_prices')
          .doc(docId);
      final existing = await docRef.get();

      final oldPrice = existing.data()?['baselinePrice'];
      final updatedBy =
          FirebaseAuth.instance.currentUser?.email ??
          FirebaseAuth.instance.currentUser?.uid ??
          'admin';
      final savedUnit = unit.isEmpty ? 'kg' : unit;
      await docRef.set({
        'name': name,
        'category': category,
        'isActive': _isActive,
        'baselinePrice': price,
        'unit': savedUnit,
        'previousBaselinePrice': oldPrice,
        'effectiveDate': Timestamp.fromDate(_effectiveDate),
        // An officer-entered price is the office's own figure.
        'source': FieldValue.delete(),
        'isTestData': false,
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      }, SetOptions(merge: true));
      // The dated history is kept on top of the price itself: if it cannot
      // be written, the price saved above still stands.
      try {
        final history = FirebaseFirestore.instance.batch();
        _recordReferencePrice(
          history,
          docRef,
          price: price,
          unit: savedUnit,
          effectiveDate: _effectiveDate,
          updatedBy: updatedBy,
        );
        await history.commit();
      } catch (e) {
        debugPrint('[PriceHistory] could not record $name: $e');
      }

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
      title: Text(
        widget.commodityId == null
            ? 'Set Admin Reference Price'
            : 'Update Admin Reference Price',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          // Room for the fields' shadows, which a scroll view would cut.
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminField(
                controller: _nameController,
                icon: Icons.eco_outlined,
                enabled: widget.commodityId == null,
                decoration: const InputDecoration(
                  labelText: 'Commodity name',
                  hintText: 'e.g. Rice',
                ),
                onChanged: (_) => _onNameChanged(),
              ),
              const SizedBox(height: 14),
              AdminField(
                controller: _categoryController,
                icon: Icons.category_outlined,
                decoration: InputDecoration(
                  labelText: 'Category',
                  hintText: 'e.g. Vegetables',
                  helperText:
                      'Existing: ${CommodityRegistry.instance.categories.join(', ')}',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 14),
              AdminField(
                controller: _priceController,
                icon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Admin reference price (₱)',
                  hintText: 'e.g. 55.00',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (_editing)
                Builder(
                  builder: (plateContext) => AdminFieldPlate(
                    label: 'Unit',
                    icon: Icons.straighten_rounded,
                    value: _unitChoice ?? 'Choose a unit',
                    helper: _unitChoice == null
                        ? 'The saved unit "${widget.initialUnit}" is not one '
                              'the app knows. Choose one.'
                        : null,
                    onTap: _saving ? null : () => _chooseUnit(plateContext),
                  ),
                )
              else
                AdminField(
                  controller: _unitController,
                  icon: Icons.straighten_rounded,
                  decoration: InputDecoration(
                    labelText: 'Unit',
                    hintText: 'e.g. kg, piece, kg liveweight',
                    helperText:
                        'Known units: ${kCommodityUnitOptions.join(', ')}',
                  ),
                ),
              const SizedBox(height: 14),
              // The date this price applies from. Every price is kept under
              // its date, so a history builds up month by month.
              AdminFieldPlate(
                label: 'Price date',
                helper: 'The date this reference price applies from.',
                icon: Icons.calendar_today_outlined,
                value: DateFormat('MMMM d, y').format(_effectiveDate),
                onTap: _saving ? null : _pickEffectiveDate,
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Active'),
                subtitle: const Text(
                  'Farmers can choose it for new products. Turning this off '
                  'keeps existing listings.',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 4),
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
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
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
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
