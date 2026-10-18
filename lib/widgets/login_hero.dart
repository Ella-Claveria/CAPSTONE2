import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'agritrade_text.dart';
import 'typewriter_headline.dart';

/// The branded header used by both [RoleSelectionScreen] (the app's front
/// door) and [LoginScreen] (its role-specific doors): the rice field at
/// sunrise, with a small, quiet AgriTrade+ lockup in the upper-left corner
/// — the logo, "AgriTrade+" beside it and the tagline under the name — and
/// rounded bottom corners. Kept as one shared widget so the two screens can
/// never quietly drift apart again.
///
/// The photo is assets/images/bg_adminside.png — the one the Admin
/// Portal's login uses too, so both doors look alike. Doesn't animate its
/// own height — the caller wraps this in an AnimatedPositioned (or
/// similar) sized however it needs.
class LoginHero extends StatelessWidget {
  final bool showBranding;
  final String tagline;

  /// Room on the left for something the screen puts in the same corner
  /// (LoginScreen's Back button), so the lockup sits beside it.
  final double leadingInset;

  /// The typed-out headline between the lockup and the sheet.
  final bool showHeadline;

  const LoginHero({
    super.key,
    required this.showBranding,
    this.tagline = 'TRADE  •  GROW  •  PROSPER',
    this.leadingInset = 0,
    this.showHeadline = true,
  });

  /// How far the screen's white sheet overlaps the bottom of the hero.
  static const double sheetOverlap = 32;

  // Soft enough to leave the photo alone, enough to lift white text off a
  // bright sky.
  static const _textShadow = [
    Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg_adminside.png',
            fit: BoxFit.cover,
            // The sunrise, mountain and fields, not just the foreground
            // rice, when cropped to the hero's band.
            alignment: const Alignment(0, -0.2),
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
          // A light dark-green tint: a little deeper along the top, behind
          // the lockup, and at the bottom edge where the white sheet takes
          // over; the middle is left nearly clear so the photo shows.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.dark.withValues(alpha: 0.55),
                  AppTheme.dark.withValues(alpha: 0.12),
                  AppTheme.dark.withValues(alpha: 0.30),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
          // Behind the headline: a soft dark-green shade from the lower
          // left, so the white text reads on the bright fields and sky.
          if (showHeadline)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-1, 0.9),
                  radius: 1.15,
                  colors: [Color(0x800E3210), Color(0x000E3210)],
                ),
              ),
            ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showBranding ? 1 : 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    // Level with LoginScreen's Back button (8 px down, 40
                    // tall).
                    padding: EdgeInsets.fromLTRB(20 + leadingInset, 8, 20, 0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(shadows: _textShadow),
                        child: const BrandLockup(),
                      ),
                    ),
                  ),
                  // The space between the lockup and the white sheet.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        12,
                        24,
                        sheetOverlap + 16,
                      ),
                      child: showHeadline
                          ? _headline()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // "Connecting Farmers to Better Markets", typed out, sized to the room
  // the screen leaves it — and left out when there is too little (a short
  // phone, or the keyboard up).
  Widget _headline() {
    return LayoutBuilder(
      builder: (context, box) {
        // About 3 lines of headline plus the subtitle: 4.4 × the size.
        final size = [
          26.0,
          box.maxWidth * 0.068,
          (box.maxHeight - 6) / BrandHeadline.heightFactor,
        ].reduce((a, b) => a < b ? a : b);
        // Hidden, not removed, when there is no room (the keyboard up), so
        // it does not type itself out again when the keyboard goes away.
        return Offstage(
          offstage: size < 15,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              // Wraps onto two or three lines, never across the photo.
              constraints: const BoxConstraints(maxWidth: 340),
              child: BrandHeadline(
                fontSize: size < 15 ? 15 : size,
                shadows: _textShadow,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The AgriTrade+ lockup on a photo: the logo, "AgriTrade+" beside it and
/// the tagline under the name, all white. Shared by the mobile login hero
/// and the Admin Portal's sign-in panel, so the two look the same; [scale]
/// sizes the whole lockup (1 is the phone's).
class BrandLockup extends StatelessWidget {
  final double scale;
  final String tagline;

  const BrandLockup({
    super.key,
    this.scale = 1,
    this.tagline = 'TRADE  •  GROW  •  PROSPER',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // logo.png has a wide transparent margin around the artwork; only
        // the artwork's own box (about half its width, three quarters of
        // its height) is kept, so the name sits right beside it.
        Align(
          widthFactor: 0.52,
          heightFactor: 0.76,
          child: Image.asset(
            'assets/images/logo.png',
            height: 56 * scale,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.agriculture, size: 40 * scale, color: Colors.white),
          ),
        ),
        SizedBox(width: 10 * scale),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AgriTradeText(fontSize: 20 * scale, light: true),
            SizedBox(height: 2 * scale),
            Text(
              tagline,
              style: TextStyle(
                fontSize: 9 * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6 * scale,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Connecting Farmers to Better Markets" (in the logo's gold), typed out,
/// then "Grow together. Trade smarter." — the same on the mobile login and
/// the Admin Portal's sign-in panel.
class BrandHeadline extends StatelessWidget {
  final double fontSize;
  final List<Shadow>? shadows;

  const BrandHeadline({super.key, required this.fontSize, this.shadows});

  /// Its height is about this many times [fontSize] (up to three lines of
  /// headline and the subtitle), for sizing it to the room it has.
  static const double heightFactor = 4.4;

  @override
  Widget build(BuildContext context) {
    return TypewriterHeadline(
      text: 'Connecting Farmers to Better Markets',
      highlight: 'Better Markets',
      // The gold of the logo's leaves (and the sunrise).
      highlightColor: const Color(0xFFF4C430),
      subtitle: 'Grow together. Trade smarter.',
      fontSize: fontSize,
      shadows: shadows,
    );
  }
}
