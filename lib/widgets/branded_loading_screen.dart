import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'walking_farmer_loader.dart';

/// The very first thing Flutter draws after the native splash hands off.
/// The circular logo stays exactly where the native splash draws it (same
/// background, same size, centred), so the handoff is invisible; under it
/// the walking-farmer loader fades in to show the app is working.
class BrandedLoadingScreen extends StatelessWidget {
  const BrandedLoadingScreen({super.key});

  static const double _logoSize = 120;

  @override
  Widget build(BuildContext context) {
    final logo = ClipOval(
      child: Image.asset(
        'assets/images/logo.png',
        width: _logoSize,
        height: _logoSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: _logoSize,
          height: _logoSize,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.agriculture, size: 60, color: AppTheme.dark),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Center(child: logo),
            // Below the logo, without moving it.
            Positioned(
              left: 0,
              right: 0,
              top: constraints.maxHeight / 2 + _logoSize / 2 + 28,
              child: const Center(child: _FadeIn(child: WalkingFarmerLoader())),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades its child in just after the screen appears, so nothing pops in
/// at the moment the native splash hands over.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> {
  // Once per app run: the loading screen is shown more than once in a row
  // while starting up, and fading in again each time made it blink.
  static bool _fadedIn = false;
  bool _shown = _fadedIn;

  @override
  void initState() {
    super.initState();
    if (_shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadedIn = true;
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _shown ? 1 : 0,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOut,
    child: widget.child,
  );
}
