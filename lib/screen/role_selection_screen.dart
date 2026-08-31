import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/agritrade_text.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const Color dark = Color.fromARGB(255, 14, 50, 16);
  static const Color _mid = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ===== Background photo (image 2 — plain, no overlays) =====
          Image.asset(
            'assets/background.png',
            fit: BoxFit.cover,
          ),

          // ===== Foreground content =====
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // ----- Logo -----
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/logo.png',
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.agriculture, size: 60, color: _mid);
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ----- "AgriTrade+" wordmark, sized to match the reference -----
                  const AgriTradeText(fontSize: 46),

                  const SizedBox(height: 10),

                  // ----- Tagline: "Grow together. Trade directly." -----
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.montserrat(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: 'Grow together. ',
                          style: TextStyle(color: Colors.grey[850]),
                        ),
                        const TextSpan(
                          text: 'Trade directly.',
                          style: TextStyle(color: _mid),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ----- Small leaf divider -----
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _leafCurve(flipped: false),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.spa, size: 18, color: _mid),
                      ),
                      _leafCurve(flipped: true),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ----- Subtitle -----
                  Text(
                    'Choose how you want to use AgriTrade',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 14.5,
                      color: Colors.grey[700],
                    ),
                  ),

                  const Spacer(flex: 3),

                  // ----- Role selection cards -----
                  _RoleCard(
                    imagePath: 'assets/farmer.png',
                    fallbackIcon: Icons.agriculture,
                    title: 'Continue as Farmer',
                    subtitle: 'List crops & livestock, manage orders',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(role: 'farmer'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    imagePath: 'assets/buyer.png',
                    fallbackIcon: Icons.shopping_cart,
                    title: 'Continue as Buyer',
                    subtitle: 'Source fresh goods',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(role: 'buyer'),
                        ),
                      );
                    },
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leafCurve({required bool flipped}) {
    return Transform.flip(
      flipX: flipped,
      child: CustomPaint(
        size: const Size(70, 16),
        painter: _LeafCurvePainter(),
      ),
    );
  }
}

class _LeafCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9CCC65).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width * 0.5, 0, size.width, size.height * 0.4);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.imagePath,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String imagePath;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color _dark = Color(0xFF1B5E20);
  static const Color _mid = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE8F5E9),
                // Swap in your own artwork by dropping a file at the
                // imagePath passed above (e.g. assets/farmer_icon.png) and
                // registering it in pubspec.yaml. Falls back to an icon
                // automatically if the asset isn't found yet.
                child: ClipOval(
                  child: Image.asset(
                    imagePath,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(fallbackIcon, color: _dark, size: 24);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.montserrat(
                        fontSize: 12.5,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _mid.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}