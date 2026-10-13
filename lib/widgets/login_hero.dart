import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'agritrade_text.dart';

/// The branded header used by both [RoleSelectionScreen] (the app's front
/// door) and [LoginScreen] (its role-specific doors) — logo + wordmark +
/// tagline over a farm landscape photo, tinted with a light dark-green
/// overlay so the white lockup stays readable, with rounded bottom corners.
/// Kept as one shared widget so the two screens can never quietly drift
/// apart again.
///
/// The photo is assets/images/login_landscape.png — replace that file to
/// change it. Doesn't animate its own height — the caller wraps this in an
/// AnimatedPositioned (or similar) sized however it needs.
class LoginHero extends StatelessWidget {
  final bool showBranding;
  final String tagline;

  const LoginHero({
    super.key,
    required this.showBranding,
    this.tagline = 'TRADE   GROW   PROSPER',
  });

  // Soft enough to leave the photo alone, enough to lift white text off a
  // bright sky or field.
  static const _textShadow = [
    Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_landscape.png',
            fit: BoxFit.cover,
            // The sky and hills, not the foreground crops, when cropped.
            alignment: const Alignment(0, -0.3),
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.dark, AppTheme.mid],
                ),
              ),
            ),
          ),
          // Dark-green tint: lighter over the sky, deeper toward the bottom
          // edge where the white sheet takes over.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.dark.withValues(alpha: 0.38),
                  AppTheme.dark.withValues(alpha: 0.46),
                  AppTheme.dark.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showBranding ? 1 : 0,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(shadows: _textShadow),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height: 84,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.agriculture,
                                size: 64,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 10),
                        const AgriTradeText(fontSize: 32, light: true),
                        const SizedBox(height: 6),
                        Text(
                          tagline,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
