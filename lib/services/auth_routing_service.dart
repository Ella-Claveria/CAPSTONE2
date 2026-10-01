import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const String _adminEmailWithoutVerification = 'admin@agritrade.com';

/// Where an authenticated user belongs, decided from their `users/{uid}`
/// Firestore document and the current platform.
///
/// The mobile build is Farmer/Buyer only; the Flutter Web build is the
/// Admin portal only (see AppBootstrap). This enum — and
/// [AuthRoutingService] below — is the ONE place that rule is enforced, so
/// every login entry point (a fresh sign-in, tapping a saved "continue as"
/// account, or resuming an already-logged-in session on cold start) goes
/// through the same check instead of each re-implementing it slightly
/// differently.
enum AuthRouteDecision {
  farmerHome,
  // PendingApprovalScreen already shows the right message for 'pending',
  // 'rejected', or a missing approvalStatus, and polls/auto-advances to
  // farmerHome once approved — so both non-approved cases route here.
  farmerPendingReview,
  buyerHome,
  emailVerificationRequired,
  adminDashboard,
  blockedAdminOnMobile,
  blockedNonAdminOnWeb,
  missingProfile,
  missingRole,
  error,
}

class AuthRouteResult {
  final AuthRouteDecision decision;
  final String? role;
  final String? message;

  const AuthRouteResult({required this.decision, this.role, this.message});

  /// Whether this account should be treated as genuinely signed in on this
  /// device (as opposed to blocked/signed back out immediately) — callers
  /// use this to decide whether to remember the login for a "continue as"
  /// tile next time.
  bool get isSignedIn => switch (decision) {
        AuthRouteDecision.blockedAdminOnMobile ||
        AuthRouteDecision.blockedNonAdminOnWeb ||
        AuthRouteDecision.missingProfile ||
        AuthRouteDecision.missingRole ||
        AuthRouteDecision.error =>
          false,
        _ => true,
      };
}

class AuthRoutingService {
  const AuthRoutingService._();

  /// Fetches `users/{uid}` (a plain, non-cached read — fine for an
  /// interactive login) and decides where the user belongs. Use
  /// [decideFromData] instead if the caller already has the document (e.g.
  /// AppRouter's offline-friendly cache-then-live fetch on cold start) —
  /// no need to read Firestore twice.
  static Future<AuthRouteResult> decide(String uid) async {
    Map<String, dynamic>? data;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) {
        return const AuthRouteResult(
          decision: AuthRouteDecision.missingProfile,
          message: 'We could not find your account details. Please contact support.',
        );
      }
      data = doc.data();
    } catch (_) {
      return const AuthRouteResult(
        decision: AuthRouteDecision.error,
        message: 'Could not verify your account. Check your connection and try again.',
      );
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    final isCurrentUser = currentUser?.uid == uid;
    final emailVerified = isCurrentUser && currentUser!.emailVerified;
    return decideFromData(
      data,
      emailVerified: emailVerified,
      authenticatedEmail: isCurrentUser ? currentUser!.email : null,
    );
  }

  /// Pure decision logic — no Firestore I/O — given a user document's data
  /// (or null/missing, which is handled the same as a missing document).
  static AuthRouteResult decideFromData(
    Map<String, dynamic>? data, {
    bool emailVerified = true,
    String? authenticatedEmail,
  }) {
    if (data == null) {
      // No users/{uid} doc yet is expected (not an error) for an account
      // that hasn't finished verifying its email — that doc is only
      // written post-verification now (see AuthService.completeRegistration
      // and EmailVerificationScreen). Role is unknown without the doc, so
      // EmailVerificationScreen falls back to its role-agnostic copy; the
      // real profile write still has the right role from registration
      // (see PendingRegistrationProfile), unaffected by this fallback.
      if (!emailVerified) {
        return const AuthRouteResult(decision: AuthRouteDecision.emailVerificationRequired);
      }
      return const AuthRouteResult(
        decision: AuthRouteDecision.missingProfile,
        message: 'We could not find your account details. Please contact support.',
      );
    }

    final role = data['role'] as String?;
    if (role != 'farmer' && role != 'buyer' && role != 'admin') {
      return AuthRouteResult(
        decision: AuthRouteDecision.missingRole,
        role: role,
        message: 'Your account is missing a role. Please contact support.',
      );
    }

    final isApprovedAdminIdentity = role == 'admin' &&
        authenticatedEmail?.trim().toLowerCase() == _adminEmailWithoutVerification;
    if (!emailVerified && !isApprovedAdminIdentity) {
      return AuthRouteResult(
        decision: AuthRouteDecision.emailVerificationRequired,
        role: role,
        message: 'Please verify your email before using AgriTrade+.',
      );
    }

    // ---- Web build: Admin Dashboard only ----
    if (kIsWeb) {
      if (role == 'admin') {
        return AuthRouteResult(decision: AuthRouteDecision.adminDashboard, role: role);
      }
      return AuthRouteResult(
        decision: AuthRouteDecision.blockedNonAdminOnWeb,
        role: role,
        message: 'This account is not authorized to access the Admin Dashboard.',
      );
    }

    // ---- Mobile build: Farmer/Buyer only ----
    if (role == 'admin') {
      return AuthRouteResult(
        decision: AuthRouteDecision.blockedAdminOnMobile,
        role: role,
        message: 'Admin accounts can only access the web-based Admin Dashboard.',
      );
    }
    if (role == 'buyer') {
      return AuthRouteResult(decision: AuthRouteDecision.buyerHome, role: role);
    }

    // role == 'farmer' — gated on approvalStatus. Farmers cannot set this
    // field themselves (AuthService/Firestore rules only let an admin
    // operation change it); we only ever read it here.
    final approvalStatus = data['approvalStatus'] as String?;
    if (approvalStatus == 'approved') {
      return AuthRouteResult(decision: AuthRouteDecision.farmerHome, role: role);
    }
    return AuthRouteResult(decision: AuthRouteDecision.farmerPendingReview, role: role);
  }
}
