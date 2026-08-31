import 'package:flutter/material.dart';
// If your role selection screen is elsewhere, fix this import + the class name below.
import '../screen/role_selection_screen.dart';

// ============================================================
// Role Mismatch dialog
// ------------------------------------------------------------
// Shows when someone logs in through the wrong role's door
// (e.g. a Buyer account signing in on the Farmer side).
// Both buttons send the user back to Role Selection.
//
// Call it like this from your login screen:
//
//   showRoleMismatchDialog(context, 'buyer');
//
// where 'buyer' is the role the account is actually registered as.
// ============================================================

const Color _darkGreen = Color(0xFF1B5E20);
const Color _midGreen = Color(0xFF2E7D32);
const Color _lightGreenAccent = Color(0xFFDCEDC8);

Future<void> showRoleMismatchDialog(
  BuildContext context,
  String registeredRole,
) {
  // "buyer" -> "Buyer"
  final roleLabel = registeredRole.isEmpty
      ? 'ibang'
      : registeredRole[0].toUpperCase() + registeredRole.substring(1);

  void goToRoleSelection(BuildContext dialogContext) {
    Navigator.of(dialogContext).pop(); // close the dialog
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false, // clear the whole back stack
    );
  }

  return showDialog(
    context: context,
    barrierDismissible: false, // they must choose a button
    builder: (dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Logo ----
              CircleAvatar(
                radius: 34,
                backgroundColor: _lightGreenAccent,
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.agriculture,
                      color: _midGreen,
                      size: 34,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---- Title ----
              const Text(
                'Role Mismatch Detected!',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _darkGreen,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ---- Message (with the role in bold) ----
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'This account is registered as '),
                    TextSpan(
                      text: roleLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _darkGreen,
                      ),
                    ),
                    TextSpan(
                      text: '. Please continue using the $roleLabel role '
                          'to access your account.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),

              // ---- Button 1: primary ----
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => goToRoleSelection(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Go to $roleLabel Login',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // ---- Button 2: secondary ----
              TextButton(
                onPressed: () => goToRoleSelection(dialogContext),
                child: const Text(
                  'Back to Role Selection',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _darkGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}