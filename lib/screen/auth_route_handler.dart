import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/agri_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import '../services/session_timeout_service.dart';
import 'admin_dashboard_screen.dart';
import 'buyer_marketplace_screen.dart';
import 'farmer_home_screen.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'role_selection_screen.dart';
import 'email_verification_screen.dart';

/// Turns an [AuthRouteResult] into the actual navigation it implies —
/// the one place every login entry point (LoginFormFields, the "continue
/// as" saved-account tile, AppRouter's cold-start resume) should call once
/// it has a decision, so the "block + sign out + explain" behavior for a
/// disallowed role/platform combination is implemented exactly once.
///
/// Always clears the navigation stack (pushAndRemoveUntil) so the device's
/// back button can never return to a screen that belonged to a role/session
/// that's no longer valid.
Future<void> applyAuthRouteResult(
  BuildContext context,
  AuthRouteResult result,
) async {
  if (result.isSignedIn) {
    SessionTimeoutService.instance.recordActivity();
  }
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
    case AuthRouteDecision.emailVerificationRequired:
      _replaceWith(
        context,
        EmailVerificationScreen(
          role: result.role ?? 'buyer',
          email: FirebaseAuth.instance.currentUser?.email ?? '',
        ),
      );
      return;
    case AuthRouteDecision.adminDashboard:
      _replaceWith(context, AdminDashboardScreen());
      return;
    case AuthRouteDecision.blockedAdminOnMobile:
    case AuthRouteDecision.blockedNonAdminOnWeb:
    case AuthRouteDecision.missingProfile:
    case AuthRouteDecision.missingRole:
    case AuthRouteDecision.accountRestricted:
      await _blockAndReturnToLogin(context, result);
      return;
    case AuthRouteDecision.error:
      // The role could not be read at all (network, Firestore hiccup) —
      // that is "unknown", not "unauthorized". On the web Admin Portal the
      // session is kept, so retrying or refreshing doesn't need a fresh
      // login; the account is only signed out once its role is confirmed.
      await _blockAndReturnToLogin(context, result, signOut: !kIsWeb);
      return;
  }
}

Future<void> _blockAndReturnToLogin(
  BuildContext context,
  AuthRouteResult result, {
  bool signOut = true,
}) async {
  final message = result.message;
  // Never rely on just hiding a screen — always fully sign the disallowed
  // session out before returning to login. Goes through AuthService (not
  // FirebaseAuth directly) so this device's FCM token is also cleaned up
  // from the blocked account — see AuthService.signOut.
  if (signOut) {
    await AuthService().signOut(
      reason:
          'route blocked: ${result.decision.name} '
          '(role: ${result.role}) — $message',
    );
  } else {
    debugPrint(
      '[Auth] route check failed (${result.decision.name}) — session kept, '
      'NOT signing out: $message',
    );
  }
  if (!context.mounted) return;

  await showAgriDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AgriDialog(
      icon: Icons.lock_outline,
      tone: AgriTone.warning,
      title: const Text('Unable to Log In'),
      content: Text(
        message ?? 'You are not able to access this at the moment.',
      ),
      actions: [
        AgriDialogButton(
          label: 'OK',
          kind: AgriButtonKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  // Web's door is the admin login; mobile's is role selection — each
  // platform returns to its own entry point, never the other's.
  _replaceWith(
    context,
    kIsWeb ? const LoginScreen(role: 'admin') : const RoleSelectionScreen(),
  );
}

void _replaceWith(BuildContext context, Widget screen) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => screen),
    (route) => false,
  );
}
