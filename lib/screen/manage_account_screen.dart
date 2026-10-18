import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/agri_app_bar.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/recovery_email_code_dialog.dart';
import 'farmer_edit_profile_screen.dart';
import 'privacy_policy_screen.dart';
import 'sign_in_activity_screen.dart';
import 'terms_and_conditions_screen.dart';
import '../l10n/tr.dart';

/// Manage Account, opened from the Profile tab's settings menu — the same
/// screen for Farmers and Buyers: one plain list in sections (personal
/// information, the account's security, the legal pages)
/// with the app version at the foot.
///
/// Notification Settings, Help & Support and Log Out are not here: they
/// are in the Profile tab's settings menu already.
class ManageAccountScreen extends StatelessWidget {
  /// Whether the recovery email is verified (null: none added — the login
  /// email does not count as one). Defaults to
  /// the signed-in account's own profile; tests pass their own.
  final Stream<bool?>? recoveryEmailVerified;

  const ManageAccountScreen({super.key, this.recoveryEmailVerified});

  static Stream<bool?> _recoveryStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          final email = (data['recoveryEmail'] ?? '').toString().trim();
          // No status until a second address (not the login email) is
          // added; Verified only once its code was entered.
          if (email.isEmpty ||
              email.toLowerCase() == (user.email ?? '').toLowerCase()) {
            return null;
          }
          return data['recoveryEmailVerified'] == true;
        });
  }

  // Read once for the app's lifetime — it cannot change while running.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final t = tr(context);
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgriAppBar(title: t.manageAccount),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _SectionLabel(t.sectionAccount),
            _SettingsRow(
              icon: Icons.person_outline,
              title: t.personalInformation,
              subtitle: t.personalInformationHint,
              onTap: () => open(const EditProfileScreen()),
            ),
            const _SectionDivider(),
            _SectionLabel(t.sectionSecurity),
            _SettingsRow(
              icon: Icons.lock_outline,
              title: t.changePassword,
              subtitle: t.changePasswordHint,
              onTap: () => showChangePasswordDialog(context),
            ),
            StreamBuilder<bool?>(
              stream: recoveryEmailVerified ?? _recoveryStatus(),
              builder: (context, snapshot) => _SettingsRow(
                icon: Icons.alternate_email_rounded,
                title: t.recoveryEmail,
                subtitle: t.recoveryEmailHint,
                // Verified / Not verified, beside the title.
                badge: snapshot.data == null
                    ? null
                    : RecoveryEmailStatusChip(verified: snapshot.data!),
                onTap: () => open(const EditProfileScreen()),
              ),
            ),
            _SettingsRow(
              icon: Icons.devices_other_outlined,
              title: t.devicesActivity,
              subtitle: t.devicesActivityHint,
              onTap: () => open(const SignInActivityScreen()),
            ),
            const _SectionDivider(),
            _SectionLabel(t.sectionAbout),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: t.privacyPolicy,
              subtitle: t.privacyPolicyHint,
              onTap: () => open(const PrivacyPolicyScreen()),
            ),
            _SettingsRow(
              icon: Icons.description_outlined,
              title: t.termsConditions,
              subtitle: t.termsConditionsHint,
              onTap: () => open(const TermsAndConditionsScreen()),
            ),
            const SizedBox(height: 24),
            // The real version from the installed build; nothing is shown
            // until (or unless) it can be read.
            FutureBuilder<PackageInfo>(
              future: _packageInfo,
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '';
                if (version.isEmpty) return const SizedBox(height: 15);
                return Text(
                  t.appVersion(version),
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
    );
  }
}

/// A small grey heading over a group of rows.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Text(
      text.toUpperCase(),
      style: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Colors.grey[600],
      ),
    ),
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Divider(height: 1, color: Colors.grey[200]),
  );
}

/// One plain row: green icon, title, short line under it, chevron.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shown right after the title (the recovery email's status).
  final Widget? badge;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppTheme.dark),
    title: badge == null
        ? Text(title)
        : Row(
            children: [
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              badge!,
            ],
          ),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.chevron_right, color: Colors.grey[500]),
    onTap: onTap,
  );
}
