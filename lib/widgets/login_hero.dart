import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'agritrade_text.dart';

/// The branded dark-green header used by both [RoleSelectionScreen] (the
/// app's front door) and [LoginScreen] (its role-specific doors) — logo +
/// wordmark + tagline over the brand gradient, with rounded bottom corners
/// and a faint leaf/vine texture. Kept as one shared widget so the two
/// screens can never quietly drift apart again.
///
/// Doesn't animate its own height — the caller wraps this in an
/// AnimatedPositioned (or similar) sized however it needs.
class LoginHero extends StatelessWidget {
  final bool showBranding;
  final String tagline;

  const LoginHero({
    super.key,
    required this.showBranding,
    this.tagline = 'TRADE   GROW   PROSPER',
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_hero.png',
            fit: BoxFit.cover,
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
          const Positioned.fill(child: _HeroLeafDecoration()),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showBranding ? 1 : 0,
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 84,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.agriculture, size: 64, color: Colors.white),
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
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint leaf silhouettes + soft sweeping vine lines over the hero
/// gradient — a light decorative texture, never so visible it competes
/// with the logo lockup sitting on top of it.
class _HeroLeafDecoration extends StatelessWidget {
  const _HeroLeafDecoration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: -30,
          top: 10,
          child: Transform.rotate(
            angle: -0.35,
            child: Icon(Icons.eco, size: 150, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Positioned(
          right: -40,
          bottom: -10,
          child: Transform.rotate(
            angle: 0.5,
            child: Icon(Icons.eco, size: 190, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _VineSwooshPainter()),
        ),
      ],
    );
  }
}

class _VineSwooshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path1 = Path()
      ..moveTo(-20, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.48, size.width * 0.75, size.height * 0.66)
      ..quadraticBezierTo(size.width * 0.95, size.height * 0.74, size.width + 20, size.height * 0.6);
    canvas.drawPath(path1, paint);

    final path2 = Path()
      ..moveTo(-20, size.height * 0.8)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.95, size.width + 20, size.height * 0.78);
    canvas.drawPath(path2, paint..color = Colors.white.withValues(alpha: 0.04));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
