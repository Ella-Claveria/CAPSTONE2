import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/push_notification_service.dart';
import '../widgets/coach_mark.dart';
import '../widgets/notification_bell.dart';
import '../widgets/unread_messages_dot.dart';
import 'add_product_screen.dart';
import 'market_tab.dart';
import 'chat_list_screen.dart';
import 'farmer_orders_tab.dart';
import 'farmer_profile_tab.dart';
import 'notifications_screen.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';

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
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _bg = Colors.white;

  // 0 = Market, 1 = Messages, 2 = Orders, 3 = Profile
  late int _selectedIndex = widget.initialIndex;

  final _addProductKey = GlobalKey();
  final _ordersTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // If the app was launched (cold start) by tapping a push notification,
    // this replays that navigation now that routing has actually finished.
    PushNotificationService.consumePendingNavigation();
    globalFarmerTabIndex.addListener(_onGlobalTabIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWalkthrough());
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
          message: 'Tap here anytime to post crops or livestock for buyers to see.',
        ),
        CoachMarkStep(
          targetKey: _ordersTabKey,
          title: 'Track incoming orders',
          message: 'Orders from buyers show up here — you can accept, message, and update their status.',
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

  // ---- Language picker ----
  void _showLanguagePicker(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final currentCode = LocaleController.instance.locale?.languageCode ?? 'en';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.selectLanguage,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              RadioGroup<String>(
                groupValue: currentCode,
                onChanged: (value) {
                  if (value == null) return;
                  LocaleController.instance.setLocale(Locale(value));
                  Navigator.pop(sheetContext);
                  _showLanguageNote(value == 'en' ? t.english : t.tagalog);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      title: Text(t.english),
                      value: 'en',
                      activeColor: _dark,
                    ),
                    RadioListTile<String>(
                      title: Text(t.tagalog),
                      value: 'tl',
                      activeColor: _dark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showLanguageNote(String language) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(AppLocalizations.of(context)!.languageChanged(language)),
      ),
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
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Exit App?'),
            content: const Text('Are you sure you want to close AgriTrade?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exit')),
            ],
          ),
        );
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          iconTheme: const IconThemeData(color: _dark),
          titleSpacing: 16,
          title: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _bg,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.agriculture, color: _dark, size: 26),
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: () => _showLanguagePicker(context),
              icon: const Icon(Icons.language, color: _dark, size: 22),
            ),
            NotificationBell(onPressed: _openNotifications, color: _dark),
            const SizedBox(width: 8),
          ],
        ),

        // ---- Bottom navigation bar (Market · Messages · + · Orders · Profile) ----
        bottomNavigationBar: BottomAppBar(
          color: Colors.white,
          elevation: 10,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _navItem(0, Icons.storefront_outlined, Icons.storefront,
                    AppLocalizations.of(context)!.navMarket),
                _navItem(1, Icons.mail_outline, Icons.mail,
                    AppLocalizations.of(context)!.navMessages, showUnreadDot: true),
                _buildAddButton(),
                _navItem(2, Icons.shopping_bag_outlined, Icons.shopping_bag,
                    AppLocalizations.of(context)!.navOrders, key: _ordersTabKey),
                _navItem(3, Icons.person_outline, Icons.person,
                    AppLocalizations.of(context)!.navProfile),
              ],
            ),
          ),
        ),

        // ---- Each tab lives in its own file now ----
        // Note: no longer `const [...]` — MarketTab now takes a callback
        // closure (onNavigateToTab), which can't be const.
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            MarketTab(onNavigateToTab: (i) => setState(() => _selectedIndex = i)),
            const ChatListScreen(),
            const OrdersTab(),
            const ProfileTab(),
          ], 
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label,
      {Key? key, bool showUnreadDot = false}) {
    final selected = _selectedIndex == index;
    final color = selected ? _dark : Colors.grey;
    final iconWidget = Icon(selected ? activeIcon : icon, color: color, size: 24);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          key: key,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            showUnreadDot ? UnreadMessagesDot(child: iconWidget) : iconWidget,
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
        child: InkWell(
          onTap: _openAddProduct,
          customBorder: const CircleBorder(),
          child: Container(
            key: _addProductKey,
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: _dark, shape: BoxShape.circle),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}