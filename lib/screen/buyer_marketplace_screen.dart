import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import 'role_selection_screen.dart';
import '../widgets/coach_mark.dart';
import '../widgets/notification_bell.dart';
import '../widgets/unread_messages_dot.dart';
import 'buyer_explore_screen.dart';
import 'chat_list_screen.dart';
import 'buyer_orders_screen.dart';
import 'buyer_profile_screen.dart';
import 'notifications_screen.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';

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
  static const Color _dark = Color(0xFF1B5E20);
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
    globalMarketplaceIndex.addListener(_onGlobalIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWalkthrough());
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
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
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.agriculture, color: _dark, size: 26),
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: () => _showLanguagePicker(context),
              icon: const Icon(Icons.language, color: _dark, size: 22),
            ),
            NotificationBell(
              key: _notificationsKey,
              color: _dark,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            const SizedBox(width: 8),
          ],
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
    return BottomAppBar(
      color: Colors.white,
      elevation: 10,
      child: SizedBox(
        height: 60,
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
    final color = selected ? _dark : Colors.grey;
    final iconWidget = Icon(
      selected ? activeIcon : icon,
      color: color,
      size: 24,
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
                  child: Text(
                    t.selectLanguage,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
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

  void _showLanguageNote(String languageName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text(
          AppLocalizations.of(context)!.languageChanged(languageName),
        ),
      ),
    );
  }
}
