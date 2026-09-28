import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import 'admin_dashboard_screen.dart';
import 'buyer_marketplace_screen.dart';
import 'farmer_home_screen.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'role_selection_screen.dart';

/// Turns an [AuthRouteResult] into the actual navigation it implies —
/// the one place every login entry point (LoginFormFields, the "continue
/// as" saved-account tile, AppRouter's cold-start resume) should call once
/// it has a decision, so the "block + sign out + explain" behavior for a
/// disallowed role/platform combination is implemented exactly once.
///
/// Always clears the navigation stack (pushAndRemoveUntil) so the device's
/// back button can never return to a screen that belonged to a role/session
/// that's no longer valid.
Future<void> applyAuthRouteResult(BuildContext context, AuthRouteResult result) async {
  switch (result.decision) {
    case AuthRouteDecision.farmerHome:
      _replaceWith(context, const FarmerHomeScreen());
      return;
    case AuthRouteDecision.farmerPendingReview:
      _replaceWith(context, const PendingApprovalScreen());
      return;
    case AuthRouteDecision.buyerHome:
      _replaceWith(context, const BuyerMarketplaceScreen());
      return;
    case AuthRouteDecision.adminDashboard:
      _replaceWith(context, AdminDashboardScreen());
      return;
    case AuthRouteDecision.blockedAdminOnMobile:
    case AuthRouteDecision.blockedNonAdminOnWeb:
    case AuthRouteDecision.missingProfile:
    case AuthRouteDecision.missingRole:
    case AuthRouteDecision.error:
      await _blockAndReturnToLogin(context, result.message);
      return;
  }
}

Future<void> _blockAndReturnToLogin(BuildContext context, String? message) async {
  // Never rely on just hiding a screen — always fully sign the disallowed
  // session out before returning to login. Goes through AuthService (not
  // FirebaseAuth directly) so this device's FCM token is also cleaned up
  // from the blocked account — see AuthService.signOut.
  await AuthService().signOut();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Unable to Sign In'),
      content: Text(message ?? 'You are not able to access this at the moment.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  // Web's door is the admin login; mobile's is role selection — each
  // platform returns to its own entry point, never the other's.
  _replaceWith(context, kIsWeb ? const LoginScreen(role: 'admin') : const RoleSelectionScreen());
}

void _replaceWith(BuildContext context, Widget screen) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => screen),
    (route) => false,
  );
}
