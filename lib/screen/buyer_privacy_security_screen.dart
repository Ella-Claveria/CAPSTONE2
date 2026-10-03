import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'buyer_saved_products_screen.dart' show buyerSubScreenAppBar;
import 'farmer_edit_profile_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_and_conditions_screen.dart';

/// Security and privacy controls for a buyer — nothing else. Changing the
/// password is the item above this one in Account Settings, so it isn't
/// repeated here.
class BuyerPrivacySecurityScreen extends StatelessWidget {
  const BuyerPrivacySecurityScreen({super.key});

  static const Color _dark = AppTheme.dark;

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buyerSubScreenAppBar('Privacy & Security'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.security_outlined, color: _dark),
            title: const Text('Recovery email'),
            subtitle: const Text('Add or verify it in your profile'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => open(const EditProfileScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: _dark),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => open(const PrivacyPolicyScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: _dark),
            title: const Text('Terms & Conditions'),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => open(const TermsAndConditionsScreen()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your email, phone number and exact address are never shown on your profile. Farmers only see the delivery details you give for an order.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colors.grey[600],
                    ),
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
