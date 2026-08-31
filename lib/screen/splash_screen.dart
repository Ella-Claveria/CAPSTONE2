import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'role_selection_screen.dart';
import 'page_transitions.dart';
import '../widgets/agritrade_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const Color _dark = Color(0xFF1B5E20);
  static const Color _mid = Color(0xFF2E7D32);

  late final AnimationController _controller;
  late final AnimationController _shimmerController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _nameFade;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _loaderFade;
  late final Animation<Offset> _loaderSlide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _logoFade = CurvedAnimation(parent: _controller, curve: const Interval(0.08, 0.40, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.08, 0.40, curve: Curves.easeOutBack)),
    );

    _nameFade = CurvedAnimation(parent: _controller, curve: const Interval(0.45, 0.75, curve: Curves.easeOut));
    _nameSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.45, 0.75, curve: Curves.easeOut)),
    );

    _loaderFade = CurvedAnimation(parent: _controller, curve: const Interval(0.75, 1.0, curve: Curves.easeOut));
    _loaderSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.75, 1.0, curve: Curves.easeOut)),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _shimmerController.forward();
    });

    Future.delayed(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        fadeSlideRoute(const RoleSelectionScreen()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ===== LOGO with shimmer sweep =====
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, child) {
                      return ShaderMask(
                        blendMode: BlendMode.srcATop,
                        shaderCallback: (bounds) {
                          final dx = bounds.width * (_shimmerController.value * 2 - 0.5);
                          return LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.75),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.35, 0.5, 0.65],
                            transform: _SlideGradient(dx / bounds.width),
                          ).createShader(bounds);
                        },
                        child: child,
                      );
                    },
                    child: Image.asset(
                      'assets/logo.png',
                      width: 140,
                      height: 140,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 140,
                          height: 140,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.agriculture, size: 70, color: _mid),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ===== Name + tagline =====
              FadeTransition(
                opacity: _nameFade,
                child: SlideTransition(
                  position: _nameSlide,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AgriTradeText(fontSize: 38),
                      const SizedBox(height: 8),
                      Text(
                        'Fresh from Farm to Table',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.grey[700],
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 50),

              // ===== Loading indicator =====
              FadeTransition(
                opacity: _loaderFade,
                child: SlideTransition(
                  position: _loaderSlide,
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(_mid),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Loading...',
                        style: GoogleFonts.montserrat(
                          fontSize: 12.5,
                          color: _dark.withValues(alpha: 0.75),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double offsetFraction;
  const _SlideGradient(this.offsetFraction);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * offsetFraction, 0, 0);
  }
}
