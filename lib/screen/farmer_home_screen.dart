import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/product_share_service.dart';
import '../services/notification_permission_prompt.dart';
import '../services/push_notification_service.dart';
import '../widgets/agri_dialog.dart';
import '../widgets/coach_mark.dart';
import '../widgets/swipeable_tabs.dart';
import '../widgets/unread_messages_dot.dart';
import '../widgets/docked_nav_bar.dart';
import '../widgets/page_header.dart';
import 'add_product_screen.dart';
import 'market_tab.dart';
import 'chat_list_screen.dart';
import 'farmer_orders_tab.dart';
import 'farmer_profile_tab.dart';
import 'notifications_screen.dart';
import '../l10n/tr.dart';

// A one-shot "command channel", not persisted UI state: setting this while
// a FarmerHomeScreen is already mounted (e.g. from a notification tap, see
// NotificationNavigationService) switches its active tab in place instead
// of pushing a second, stacked Home screen. A fresh FarmerHomeScreen always
// takes its starting tab from its own `initialIndex` constructor argument,
// never from whatever this notifier was last set to.
final ValueNotifier<int> globalFarmerTabIndex = ValueNotifier<int>(0);

class FarmerHomeScreen extends StatefulWidget {
  final int initialIndex;

  const FarmerHomeScreen({super.key, this.initialIndex = 0});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  static const Color _dark = AppTheme.dark;
  static const Color _bg = Colors.white;

  // 0 = Market, 1 = Messages, 2 = Orders, 3 = Profile
  late int _selectedIndex = widget.initialIndex;

  // The bottom bar slides away while a long page is scrolled down
  // (NavBarAutoHide), and is back on any scroll up or tab change.
  bool _navHidden = false;
  void _setNavHidden(bool hidden) {
    if (hidden != _navHidden && mounted) setState(() => _navHidden = hidden);
  }

  final _addProductKey = GlobalKey();
  final _ordersTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // If the app was launched (cold start) by tapping a push notification,
    // this replays that navigation now that routing has actually finished.
    PushNotificationService.consumePendingNavigation();
    // Likewise for a shared product link that opened the app.
    ProductLinkService.homeReady();
    globalFarmerTabIndex.addListener(_onGlobalTabIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEnteredApp());
  }

  // Runs once this home screen is actually on screen — i.e. after login,
  // email verification and admin approval are all behind the user. The
  // notification rationale waits for the first-time walkthrough so the two
  // never appear on top of each other.
  Future<void> _onEnteredApp() async {
    await _showWalkthrough();
    if (!mounted) return;
    await NotificationPermissionPrompt.instance.onEnteredApp(context);
  }

  void _onGlobalTabIndexChanged() {
    if (!mounted) return;
    setState(() => _selectedIndex = globalFarmerTabIndex.value);
  }

  @override
  void dispose() {
    globalFarmerTabIndex.removeListener(_onGlobalTabIndexChanged);
    super.dispose();
  }

  // A one-time, subtle tour pointing at the two things a brand-new farmer
  // most needs to find: posting their first listing, and where incoming
  // orders will show up.
  Future<void> _showWalkthrough() async {
    if (!mounted) return;
    await showCoachMarksOnce(
      context: context,
      prefsKey: 'walkthrough_seen_farmer',
      steps: [
        CoachMarkStep(
          targetKey: _addProductKey,
          title: 'List your first product',
          message:
              'Tap here anytime to post crops or livestock for buyers to see.',
        ),
        CoachMarkStep(
          targetKey: _ordersTabKey,
          title: 'Track incoming orders',
          message:
              'Orders from buyers show up here — you can accept, message, and update their status.',
        ),
      ],
    );
  }

  void _openAddProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // On a non-Market tab, the back button returns to Market first.
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
        final shouldExit = await showAgriConfirm(
          context: context,
          icon: Icons.exit_to_app,
          title: tr(context).exitAppTitle,
          message: tr(context).exitAppMessage,
          confirmLabel: tr(context).exit,
        );
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        // ---- Bottom navigation bar (Market · Messages · + · Orders · Profile) ----
        // Docked to the bottom edge (not floating), Android-style.
        bottomNavigationBar: DockedNavBar(
          hidden: _navHidden,
          children: [
            _navItem(
              0,
              Icons.storefront_outlined,
              Icons.storefront,
              tr(context).navMarket,
            ),
            _navItem(
              1,
              Icons.mail_outline,
              Icons.mail,
              tr(context).navMessages,
              showUnreadDot: true,
            ),
            _buildAddButton(),
            _navItem(
              2,
              Icons.shopping_bag_outlined,
              Icons.shopping_bag,
              tr(context).navOrders,
              key: _ordersTabKey,
            ),
            _navItem(
              3,
              Icons.person_outline,
              Icons.person,
              tr(context).navProfile,
            ),
          ],
        ),

        // ---- Each tab lives in its own file now ----
        // Note: no longer `const [...]` — MarketTab now takes a callback
        // closure (onNavigateToTab), which can't be const.
        // No app bar: every tab starts with its own green header — logo and
        // title, see PageHeader — and the status bar strip above it is the
        // same green (PageHeaderSafeArea).
        body: PageHeaderSafeArea(
          // Swipe left or right to move between the tabs, as well as
          // tapping them in the bar below.
          child: NavBarAutoHide(
            onHiddenChanged: _setNavHidden,
            child: SwipeableTabs(
              index: _selectedIndex,
              onIndexChanged: (i) => setState(() {
                _selectedIndex = i;
                _navHidden = false;
              }),
              children: [
                MarketTab(
                  onNavigateToTab: (i) => setState(() => _selectedIndex = i),
                  onNotificationsPressed: _openNotifications,
                ),
                const ChatListScreen(),
                const OrdersTab(),
                const ProfileTab(),
              ],
            ),
          ),
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
    final selected = _selectedIndex == index;
    final color = selected ? _dark : const Color(0xFFAAB4AC);
    final iconWidget = Icon(
      selected ? activeIcon : icon,
      color: color,
      size: 20,
    );
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedIndex = index;
          _navHidden = false;
        }),
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

  Widget _buildAddButton() {
    return Expanded(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -17),
          child: InkWell(
            onTap: _openAddProduct,
            customBorder: const CircleBorder(),
            child: Container(
              key: _addProductKey,
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _dark,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _dark.withValues(alpha: 0.30),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 31),
            ),
          ),
        ),
      ),
    );
  }
}
