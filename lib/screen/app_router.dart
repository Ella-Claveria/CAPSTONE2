import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'role_selection_screen.dart';
import 'onboarding_screen.dart';
import 'page_transitions.dart';
import 'auth_route_handler.dart';
import '../services/auth_routing_service.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/push_notification_service.dart';
import '../services/session_timeout_service.dart';
import '../widgets/branded_loading_screen.dart';
import '../widgets/no_internet_screen.dart';

/// Gatekeeper shown right after the native splash: a fresh install sees the
/// onboarding carousel first, then every launch — first-run or not — sends
/// the app straight to the right screen. Whoever's already logged in on this
/// device goes straight to their home screen, and everyone else goes to role
/// selection, which shows a one-tap "continue as" option for any account
/// saved on this device.
///
/// AgriTrade+ requires current approval/role data, so the user doc is
/// always read live (`Source.server`) here — never from Firestore's local
/// cache — and a failed read is treated as "offline", not as "show
/// whatever we last saw" (AppBootstrap already confirms connectivity
/// before this screen is ever reached; this is only a defensive fallback
/// for a connection that drops in that split second, or a slow network).
///

/// Deliberately does NOT request location or notification permissions —
/// those are asked for contextually, the first time the user reaches a
/// feature that actually needs them (see [BuyerMarketView] for location and
/// [NotificationsScreen] for push notifications).
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  static const _onboardingCompleteKey = 'onboarding_complete';

  bool? _needsOnboarding;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    bool done = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      done = prefs.getBool(_onboardingCompleteKey) ?? false;
    } catch (_) {
      // Nothing cached yet — treat this as a first-time install.
    }
    if (!mounted) return;
    if (done) {
      // Returning device: onboarding already happened on some earlier
      // launch, so this is just a silent token refresh, not a first-open
      // permission ask — requestPermission() no-ops with no dialog once the
      // user has already answered it once.
      try {
        await PushNotificationService().setupFCM();
      } catch (_) {
        // Non-fatal — must never block routing.
      }
      if (!mounted) return;
      _route();
    } else {
      setState(() => _needsOnboarding = true);
    }
  }

  Future<void> _finishOnboarding() async {
    // Deliberately no permission requests here — "Skip" and "Get Started"
    // both just leave onboarding. Location, notifications, camera, etc. are
    // asked for the first time the user reaches a feature that needs them.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompleteKey, true);
    } catch (_) {
      // Not fatal — worst case they see onboarding again next launch.
    }
    if (!mounted) return;
    await _route();
  }

  Future<void> _route() async {
    if (mounted && _offline) setState(() => _offline = false);

    // Covers the app having been killed outright while backgrounded for
    // 15+ minutes — SessionTimeoutService's own lifecycle observer only
    // catches a timeout on resume while the process survived; this cold
    // start is the other half of the same rule. A no-op otherwise.
    await SessionTimeoutService.instance.signOutIfIdleTooLong();
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Role selection itself now shows any saved accounts for this device
      // (one tap to continue as whichever one still holds the live Firebase
      // session, a quick email-prefilled login for any other saved one).
      if (!mounted) return;
      _goTo(const RoleSelectionScreen());
      return;
    }

    try {
      await user.reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _offline = true);
      return;
    }
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null) {
      if (!mounted) return;
      _goTo(const RoleSelectionScreen());
      return;
    }
    if (refreshedUser.emailVerified) {
      final verificationError = await AuthService().refreshVerifiedEmailToken();
      if (verificationError != null) {
        if (!mounted) return;
        setState(() => _offline = true);
        return;
      }
    }

    // Always a live, server-confirmed read — never Firestore's local cache.
    // A stale cached doc could still show an old approval status or role,
    // which is exactly what this account must never be routed on.
    Map<String, dynamic>? data;
    var reachable = true;
    try {
      final live = await FirebaseFirestore.instance
          .collection('users')
          .doc(refreshedUser.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      data = live.data();
    } catch (_) {
      reachable = false;
    }

    if (!mounted) return;

    if (!reachable) {
      // Couldn't confirm current data at all — a connectivity problem, not
      // an invalid account. Stay on this device's real state rather than
      // guessing at a destination from data that might already be stale.
      setState(() => _offline = true);
      return;
    }

    // We have real profile data, so from here on this goes through the
    // exact same mobile-only (Farmer/Buyer) and farmer-approval-status
    // rules as a fresh login — resuming an already-logged-in session on
    // cold start must never be able to skip them (e.g. a farmer whose
    // application was rejected after their last session, or — in
    // principle — an admin account somehow still signed in on this
    // device).
    final result = AuthRoutingService.decideFromData(
      data,
      emailVerified: refreshedUser.emailVerified,
      authenticatedEmail: refreshedUser.email,
    );
    await applyAuthRouteResult(context, result);
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(context, fadeSlideRoute(screen));
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) {
      return NoInternetScreen(message: kNoInternetMessage, onRetry: _route);
    }
    if (_needsOnboarding == true) {
      return OnboardingScreen(onGetStarted: _finishOnboarding);
    }

    return const BrandedLoadingScreen();
  }
}
