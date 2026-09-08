import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'role_selection_screen.dart';
import 'farmer_home_screen.dart';
import 'buyer_marketplace_screen.dart';
import 'onboarding_screen.dart';
import 'page_transitions.dart';
import '../services/push_notification_service.dart';
import '../widgets/branded_loading_screen.dart';

/// Gatekeeper shown right after the native splash: a fresh install sees the
/// onboarding carousel first, then every launch — first-run or not — sends
/// the app straight to the right screen. Whoever's already logged in on this
/// device goes straight to their home screen, and everyone else goes to role
/// selection, which shows a one-tap "continue as" option for any account
/// saved on this device. Reads the cached copy of their user doc first so
/// this works even with no internet connection; only falls back to a live
/// (timeout-guarded) read if nothing is cached yet, and only falls back to
/// role selection if neither works.
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Role selection itself now shows any saved accounts for this device
      // (one tap to continue as whichever one still holds the live Firebase
      // session, a quick email-prefilled login for any other saved one).
      if (!mounted) return;
      _goTo(const RoleSelectionScreen());
      return;
    }

    final usersRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    String? role;

    try {
      final cached = await usersRef.get(const GetOptions(source: Source.cache));
      role = cached.data()?['role'] as String?;
    } catch (_) {
      // No cached copy yet — fall through to a live read below.
    }

    if (role == null) {
      try {
        final live = await usersRef.get().timeout(const Duration(seconds: 4));
        role = live.data()?['role'] as String?;
      } catch (_) {
        // Offline with nothing cached yet — nothing more to try.
      }
    }

    if (!mounted) return;
    switch (role) {
      case 'farmer':
        _goTo(const FarmerHomeScreen());
        break;
      case 'buyer':
        _goTo(const BuyerMarketplaceScreen());
        break;
      default:
        _goTo(const RoleSelectionScreen());
    }
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(context, fadeSlideRoute(screen));
  }

  @override
  Widget build(BuildContext context) {
    if (_needsOnboarding == true) {
      return OnboardingScreen(onGetStarted: _finishOnboarding);
    }

    return const BrandedLoadingScreen();
  }
}
