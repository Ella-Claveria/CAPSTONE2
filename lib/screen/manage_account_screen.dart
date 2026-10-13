import 'notification_preferences_screen.dart';
import '../widgets/agri_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/change_password_dialog.dart';
import 'account_settings_screen.dart';
import 'farmer_edit_profile_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_and_conditions_screen.dart';
import 'sign_in_activity_screen.dart';

/// One rounded option card: a green icon, a title with a subtitle under
/// it, and a chevron. Used for the Manage Account entry on the farmer's
/// Profile tab and for every option on the Manage Account screen itself.
class AccountOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const AccountOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.mid, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[500]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

PreferredSizeWidget _manageAppBar(String title) => AgriAppBar(title: title);

/// Manage Account, opened from the farmer's Profile tab: the account
/// options as separate cards, with the app version at the foot. Log Out
/// is not here — it sits in the Profile tab's three-dot menu.
class ManageAccountScreen extends StatelessWidget {
  const ManageAccountScreen({super.key});

  // Read once for the app's lifetime — it cannot change while running.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _manageAppBar('Manage Account'),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    AccountOptionCard(
                      icon: Icons.settings_outlined,
                      title: 'Account Settings',
                      subtitle:
                          'Manage your account, personal information, and preferences.',
                      onTap: () => open(const AccountSettingsScreen()),
                    ),
                    const SizedBox(height: 12),
                    AccountOptionCard(
                      icon: Icons.shield_outlined,
                      title: 'Privacy & Security',
                      subtitle:
                          'Manage your privacy settings and account security.',
                      onTap: () => open(const _PrivacySecurityScreen()),
                    ),
                    const SizedBox(height: 12),
                    AccountOptionCard(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notification Preferences',
                      subtitle:
                          'Set your notification preferences for orders, messages, and updates.',
                      onTap: () => open(const NotificationPreferencesScreen()),
                    ),
                    const SizedBox(height: 12),
                    AccountOptionCard(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      subtitle: 'Get help, contact support, and view FAQs.',
                      onTap: () => AccountSettingsScreen.showHelp(context),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    // The real version from the installed build; nothing is
                    // shown until (or unless) it can be read.
                    FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        final version = snapshot.data?.version ?? '';
                        if (version.isEmpty) return const SizedBox(height: 15);
                        return Text(
                          'AgriTrade+ • Version $version',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 11.5,
                            color: Colors.grey[500],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Password, recovery email and the legal pages — the same actions the
// farmer already had, gathered on one screen.
class _PrivacySecurityScreen extends StatelessWidget {
  const _PrivacySecurityScreen();

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _manageAppBar('Privacy & Security'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        children: [
          AccountOptionCard(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update the password you log in with.',
            onTap: () => showChangePasswordDialog(context),
          ),
          const SizedBox(height: 12),
          AccountOptionCard(
            icon: Icons.devices_other_outlined,
            title: 'Devices & Login Activity',
            subtitle: 'Where your account is logged in, and login alerts.',
            onTap: () => open(const SignInActivityScreen()),
          ),
          AccountOptionCard(
            icon: Icons.security_outlined,
            title: 'Recovery Email',
            subtitle: 'Add or verify it in your profile.',
            onTap: () => open(const EditProfileScreen()),
          ),
          const SizedBox(height: 12),
          AccountOptionCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How AgriTrade+ handles your information.',
            onTap: () => open(const PrivacyPolicyScreen()),
          ),
          const SizedBox(height: 12),
          AccountOptionCard(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            subtitle: 'The rules for using AgriTrade+.',
            onTap: () => open(const TermsAndConditionsScreen()),
          ),
        ],
      ),
    );
  }
}
