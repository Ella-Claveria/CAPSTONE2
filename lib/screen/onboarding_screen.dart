import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/agritrade_text.dart';

/// First-run intro carousel — shown once on a fresh install, before the app
/// routes to role selection or login. Both "Skip" and reaching the last card
/// ("Get Started") leave onboarding the same way — permissions are never
/// requested here; each feature that actually needs one (location, chat
/// notifications, ...) asks for it the first time the user reaches that
/// feature. [onGetStarted] is awaited (and the button disabled meanwhile)
/// because it's the hook the caller uses to persist the "already onboarded"
/// flag before moving on.
class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onGetStarted;

  const OnboardingScreen({super.key, required this.onGetStarted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardPage {
  final IconData icon;
  final String title;
  final String description;
  final String imagePath;
  final bool isBrand;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.imagePath,
    this.isBrand = false,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_OnboardPage> _pages = [
    _OnboardPage(
      icon: Icons.agriculture_outlined,
      title: 'Welcome to AgriTrade+',
      description: 'Connecting local farmers directly with buyers — fresh produce, fair prices, no middlemen.',
      imagePath: 'assets/background.png',
      isBrand: true,
    ),
    _OnboardPage(
      icon: Icons.storefront_outlined,
      title: 'Discover Fresh Produce',
      description: 'Browse listings from verified farmers near you and order fruits, vegetables, and livestock in just a few taps.',
      imagePath: 'assets/farmers.png',
    ),
    _OnboardPage(
      icon: Icons.notifications_active_outlined,
      title: 'Stay Connected',
      description: 'Chat with sellers, track your orders, and get notified the moment something changes.',
      imagePath: 'assets/taalview.png',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;
  bool _submitting = false;

  bool get _isLastPage => _index == _pages.length - 1;

  void _next() {
    if (_isLastPage) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  // Skip means "let me dive straight in" — it should leave onboarding
  // entirely, not just fast-forward to the last card.
  void _skip() => _finish();

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.onGetStarted();
    if (mounted) setState(() => _submitting = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _textShadow = [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _OnboardPageView(page: _pages[i]),
          ),

          // ----- Skip, top-right -----
          if (!_isLastPage)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 4),
                  child: TextButton(
                    onPressed: _submitting ? null : _skip,
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: _textShadow,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ----- Dots + Next/Get Started, floating directly over the photo -----
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                              )
                            : Text(
                                _isLastPage ? 'Get Started' : 'Next',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
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

class _OnboardPageView extends StatelessWidget {
  final _OnboardPage page;
  const _OnboardPageView({required this.page});

  static const Color _dark = Color(0xFF1B5E20);
  static const _darkTextShadow = [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2))];
  // A soft white halo behind dark brand text — keeps "Welcome to" and the
  // description readable even where the photo underneath isn't perfectly
  // light, without needing a solid scrim over the whole image.
  static const _lightTextShadow = [
    Shadow(color: Colors.white, blurRadius: 12),
    Shadow(color: Colors.white, blurRadius: 12),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ----- Full-bleed photo, no overlay -----
        Image.asset(page.imagePath, fit: BoxFit.cover),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Sits the branding/icon block in the upper portion of the
                // photo (each image's lightest, least busy area) instead of
                // dead-center, so the text stays legible with no scrim.
                const SizedBox(height: 56),
                if (page.isBrand) ...[
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(8),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.agriculture, size: 54, color: _dark),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome to',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      shadows: _lightTextShadow,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AgriTradeText(fontSize: 36),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    page.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      height: 1.5,
                      color: Colors.black87,
                      shadows: _lightTextShadow,
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Icon(page.icon, size: 66, color: _dark),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, shadows: _darkTextShadow),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    page.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14.5, height: 1.5, color: Colors.white, shadows: _darkTextShadow),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
