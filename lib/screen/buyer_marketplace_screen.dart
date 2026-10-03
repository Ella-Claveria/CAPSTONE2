import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/product_share_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import 'role_selection_screen.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/coach_mark.dart';
import '../widgets/agri_header.dart';
import '../widgets/unread_messages_dot.dart';
import 'buyer_explore_screen.dart';
import 'chat_list_screen.dart';
import 'buyer_orders_screen.dart';
import 'buyer_profile_screen.dart';
import 'notifications_screen.dart';
import '../l10n/app_localizations.dart';

// A one-shot "command channel", not persisted UI state — see the matching
// comment on globalFarmerTabIndex in farmer_home_screen.dart.
final ValueNotifier<int> globalMarketplaceIndex = ValueNotifier<int>(0);

class BuyerMarketplaceScreen extends StatefulWidget {
  final int initialIndex;

  const BuyerMarketplaceScreen({super.key, this.initialIndex = 0});

  @override
  State<BuyerMarketplaceScreen> createState() => _BuyerMarketplaceScreenState();
}

class _BuyerMarketplaceScreenState extends State<BuyerMarketplaceScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _bg = Colors.white;

  late int _navIndex;

  final _notificationsKey = GlobalKey();
  final _ordersTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _navIndex = widget
        .initialIndex; // Properly initializes to index 1 (Messages) when passed from chat
    // If the app was launched (cold start) by tapping a push notification,
    // this replays that navigation now that routing has actually finished.
    PushNotificationService.consumePendingNavigation();
    // Likewise for a shared product link that opened the app.
    ProductLinkService.homeReady();
    globalMarketplaceIndex.addListener(_onGlobalIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnteredApp());
  }

  // Runs once this home screen is actually on screen — i.e. after login
  // and email verification are behind the user. The notification rationale
  // waits for the first-time walkthrough so the two never appear on top of
  // each other.
  Future<void> _onEnteredApp() async {
    await _showWalkthrough();
    if (!mounted) return;
    await NotificationPermissionPrompt.instance.onEnteredApp(context);
  }

  void _onGlobalIndexChanged() {
    if (!mounted) return;
    setState(() => _navIndex = globalMarketplaceIndex.value);
  }

  @override
  void dispose() {
    globalMarketplaceIndex.removeListener(_onGlobalIndexChanged);
    super.dispose();
  }

  // A one-time, subtle tour pointing at the two things a brand-new buyer
  // most needs to find: where updates land, and where their orders show up.
  Future<void> _showWalkthrough() async {
    if (!mounted) return;
    await showCoachMarksOnce(
      context: context,
      prefsKey: 'walkthrough_seen_buyer',
      steps: [
        CoachMarkStep(
          targetKey: _notificationsKey,
          title: 'Stay updated',
          message: 'New messages from farmers and order updates show up here.',
        ),
        CoachMarkStep(
          targetKey: _ordersTabKey,
          title: 'Track your orders',
          message:
              'Everything you order shows up here, from pending to delivered.',
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showAgriConfirm(
      context: context,
      icon: Icons.logout,
      tone: AgriTone.destructive,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
    );
    if (!confirm) return;
    await AuthService().logOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const BuyerExploreScreen(),
      const ChatListScreen(),
      BuyerOrdersScreen(
        onBrowseMarketplace: () => setState(() => _navIndex = 0),
      ),
      BuyerProfileScreen(onLogout: () => _logout(context)),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_navIndex != 0) {
          setState(() => _navIndex = 0);
        } else {
          await _logout(context);
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AgriHeader(
          bellKey: _notificationsKey,
          onLogoTap: () => setState(() => _navIndex = 0),
          onNotificationsPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
        body: SafeArea(
          child: IndexedStack(index: _navIndex, children: pages),
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final t = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.72),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8EB99A).withValues(alpha: 0.22),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            _navItem(0, Icons.explore_outlined, Icons.explore, t.navExplore),
            _navItem(
              1,
              Icons.mail_outline,
              Icons.mail,
              t.navMessages,
              showUnreadDot: true,
            ),
            _navItem(
              2,
              Icons.shopping_bag_outlined,
              Icons.shopping_bag,
              t.navOrders,
              key: _ordersTabKey,
            ),
            _navItem(3, Icons.person_outline, Icons.person, t.navProfile),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    Key? key,
    bool showUnreadDot = false,
  }) {
    final selected = _navIndex == index;
    final color = selected ? _dark : const Color(0xFFAAB4AC);
    final iconWidget = Icon(
      selected ? activeIcon : icon,
      color: color,
      size: 20,
    );
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _navIndex = index),
        child: Column(
          key: key,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            showUnreadDot ? UnreadMessagesDot(child: iconWidget) : iconWidget,
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
