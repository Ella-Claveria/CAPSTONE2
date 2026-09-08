import 'package:flutter/material.dart';
import '../widgets/change_password_dialog.dart';

class BuyerProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const BuyerProfileScreen({super.key, required this.onLogout});

  @override
  State<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends State<BuyerProfileScreen> {
  static const Color _dark = Color(0xFF1B5E20);

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _dark,
      onRefresh: _refreshData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Color(0xFFDCEDC8),
                    child: Icon(Icons.person, size: 36, color: _dark),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: _dark),
                    onPressed: () => showChangePasswordDialog(context),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Change Password'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _dark, foregroundColor: Colors.white),
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log Out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}