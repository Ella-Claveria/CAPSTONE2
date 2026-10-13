import 'package:flutter/material.dart';

import 'agri_dialog.dart';

/// Asked at Admin login when the account is in use on another browser.
/// True when the Admin chooses to continue and sign the other one out.
Future<bool> showAdminSessionConflictDialog(BuildContext context) async {
  final result = await showAgriDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.devices_other_outlined,
      tone: AgriTone.warning,
      title: const Text('Account already logged in'),
      content: const Text(
        'This Admin account is currently active on another device. '
        'Continuing will sign out the previous session.',
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AgriDialogButton(
          label: 'Continue & Sign Out Other Device',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shown on the browser whose Admin session was ended by a sign-in
/// elsewhere, once it is back at the login page.
Future<void> showAdminSessionEndedDialog(BuildContext context) {
  return showAgriDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.logout_rounded,
      tone: AgriTone.warning,
      title: const Text('Session ended'),
      content: const Text(
        'Your Admin account was logged in on another device.',
      ),
      actions: [
        AgriDialogButton(
          label: 'Back to Login',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}
