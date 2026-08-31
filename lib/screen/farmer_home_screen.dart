import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/message_service.dart';
import '../widgets/agritrade_text.dart';
import 'add_product_screen.dart';
import 'market_tab.dart';
import 'chat_list_screen.dart';
import 'farmer_orders_tab.dart';
import 'farmer_profile_tab.dart';
import 'notifications_screen.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _bg = Color(0xFFF7F9F5);

  final MessageService _messageService = MessageService();

  // 0 = Market, 1 = Messages, 2 = Orders, 3 = Profile
  int _selectedIndex = 0;

  // Session-only for now — see chat notes on full localization.
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    // Register this device for push notifications so new messages can
    // reach the farmer even when the app is backgrounded.
    _messageService.registerFcmToken();
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Language',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              RadioGroup<String>(
                groupValue: _language,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _language = value);
                  Navigator.pop(sheetContext);
                  _showLanguageNote(value == 'en' ? 'English' : 'Tagalog');
                },
                child: Column(
                  children: [
                    const RadioListTile<String>(
                      title: Text('English'),
                      value: 'en',
                      activeColor: _dark,
                    ),
                    const RadioListTile<String>(
                      title: Text('Tagalog'),
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
        content: Text('Language set to $language. Full app translation coming soon.'),
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
          title: Row(
            children: [
              Image.asset('assets/logo.png', height: 44,
                  errorBuilder: (c, e, s) => const Icon(Icons.agriculture, color: _dark)),
              const SizedBox(width: 8),
              const AgriTradeText(fontSize: 22),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => _showLanguagePicker(context),
              icon: const Icon(Icons.language, color: _dark, size: 22),
            ),
            IconButton(
              onPressed: _openNotifications,
              icon: const Icon(Icons.notifications_none_rounded, color: _dark, size: 22),
            ),
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
                _navItem(0, Icons.storefront_outlined, Icons.storefront, 'Market'),
                _navItem(1, Icons.mail_outline, Icons.mail, 'Messages'),
                _buildAddButton(),
                _navItem(2, Icons.shopping_bag_outlined, Icons.shopping_bag, 'Orders'),
                _navItem(3, Icons.person_outline, Icons.person, 'Profile'),
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

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _selectedIndex == index;
    final color = selected ? _dark : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 24),
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