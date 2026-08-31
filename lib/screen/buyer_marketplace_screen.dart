import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'role_selection_screen.dart';
import '../widgets/agritrade_text.dart';
import 'buyer_explore_screen.dart';
import 'chat_list_screen.dart';
import 'buyer_orders_screen.dart';
import 'buyer_profile_screen.dart';

final ValueNotifier<int> globalMarketplaceIndex = ValueNotifier<int>(0);

class BuyerMarketplaceScreen extends StatefulWidget {
  final int initialIndex;
  
  const BuyerMarketplaceScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<BuyerMarketplaceScreen> createState() => _BuyerMarketplaceScreenState();
}

class _BuyerMarketplaceScreenState extends State<BuyerMarketplaceScreen> {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _bg = Color(0xFFF7F9F5);

  late int _navIndex;
  String language = 'en';

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialIndex; // Properly initializes to index 1 (Messages) when passed from chat
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
      const BuyerOrdersScreen(),
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
          title: Row(
            children: [
              Image.asset('assets/logo.png', height: 44, errorBuilder: (c, e, s) => const Icon(Icons.agriculture, color: _dark)),
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
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, color: _dark, size: 22),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _navIndex,
            children: pages,
          ),
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomAppBar(
      color: Colors.white,
      elevation: 10,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _navItem(0, Icons.explore_outlined, Icons.explore, 'Explore'),
            _navItem(1, Icons.mail_outline, Icons.mail, 'Messages'),
            _navItem(2, Icons.shopping_bag_outlined, Icons.shopping_bag, 'Orders'),
            _navItem(3, Icons.person_outline, Icons.person, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _navIndex == index;
    final color = selected ? _dark : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _navIndex = index),
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
                  child: Text('Select Language', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              RadioGroup<String>(
                groupValue: language,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => language = value);
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

  void _showLanguageNote(String languageName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: _dark,
        content: Text('Language set to $languageName. Full app translation coming soon.'),
      ),
    );
  }
}