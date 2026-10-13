import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/change_email_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/login_form_fields.dart';
import 'admin_filter_controls.dart';
import 'admin_notifications.dart';
import 'admin_sub_nav.dart';

// The Admin's own account, reached from the avatar in the header: Manage
// Account, with the account's details and its settings.

/// The Admin's name as stored on their account, or "Admin" when none is.
Future<String> _adminName() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'Admin';
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    for (final value in [
      doc.data()?['fullName'],
      doc.data()?['name'],
      user.displayName,
    ]) {
      final name = (value ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
  } catch (_) {
    // Falls through to the plain role name.
  }
  return 'Admin';
}

/// Avatar > Manage Account: the account's details and its settings, each
/// in its own section. Changing the email or password opens the same
/// re-authenticating dialogs as before.
Future<void> showAdminManageAccount(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManageAccount(),
  );
}

class _ManageAccount extends StatefulWidget {
  const _ManageAccount();

  @override
  State<_ManageAccount> createState() => _ManageAccountState();
}

class _ManageAccountState extends State<_ManageAccount> {
  late final Future<String> _name = _adminName();
  final _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.62);
    // Read each build, so a changed email shows once its dialog closes.
    final email = _auth.currentEmail ?? 'Not available';
    final googleOnly = !_auth.hasPasswordProvider;

    Widget section(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: adminActionOf(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );

    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    Widget setting({
      required IconData icon,
      required String title,
      required String note,
      required String action,
      required VoidCallback onPressed,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The portal's standard pill button, the same width on every
          // row so they line up down the right edge.
          SizedBox(
            width: 104,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(action),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Manage Account'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section('Account Information', [
                FutureBuilder<String>(
                  future: _name,
                  builder: (context, snapshot) =>
                      detail('Full name', snapshot.data ?? '…'),
                ),
                detail('Email', email),
                detail('Role', 'Administrator'),
              ]),
              section('Email', [
                setting(
                  icon: Icons.mail_outline_rounded,
                  title: 'Change Email',
                  note: email,
                  action: 'Change',
                  onPressed: () async {
                    await showChangeEmailDialog(context);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
              section('Password', [
                setting(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  note: googleOnly
                      ? 'Managed by your Google Account'
                      : 'Requires your current password',
                  action: 'Change',
                  onPressed: () async {
                    // Forget the password saved for the login form once it
                    // has actually changed.
                    if (await showChangePasswordDialog(context)) {
                      await LoginFormFields.clearSavedAdminPassword();
                    }
                  },
                ),
              ]),
              section('Security and Login', [
                setting(
                  icon: Icons.history_rounded,
                  title: 'Login Activity',
                  note:
                      'Every login, failed attempt and sign-out, in the '
                      'Audit Log',
                  action: 'View',
                  onPressed: () {
                    Navigator.of(context).pop();
                    AdminSubNav.audit.value = AuditSection.login;
                    adminOpenPageRequest.value =
                        AdminNotificationTarget.auditLog;
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
