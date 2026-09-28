import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

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

/// One onboarding card's content. A single reusable page widget
/// ([_OnboardPageView]) renders every item, instead of three near-identical
/// screens.
class _OnboardingItem {
  final String image;
  final String title;
  final String description;
  const _OnboardingItem({required this.image, required this.title, required this.description});
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_OnboardingItem> _items = [
    _OnboardingItem(
      image: 'assets/images/onboarding_1_farming.png',
      title: 'Discover Fresh Produce',
      description: 'Find fresh products directly from verified local farmers.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding_2_connection.png',
      title: 'Support Local Farmers',
      description: 'Connect with local farmers and livestock raisers in your community.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding_3_marketplace.png',
      title: 'Trade with Confidence',
      description: 'List products, place orders, and receive important transaction updates in one place.',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;
  bool _submitting = false;

  bool get _isLastPage => _index == _items.length - 1;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _OnboardPageView(item: _items[i]),
          ),

          // ----- Skip, top-right — hidden on the last page since Get -----
          // ----- Started already finishes onboarding the same way. -----
          if (!_isLastPage)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 20, top: 8),
                  child: TextButton(
                    onPressed: _submitting ? null : _skip,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.montserrat(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),

          // ----- Title, description, page indicator, action button — all -----
          // ----- anchored to the lower section, over the darkest part of  -----
          // ----- each photo's gradient. -----
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The only motion besides the page swipe itself: a
                    // small fade/slide when the title and description
                    // change, instead of hard-cutting.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey<int>(_index),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _items[_index].title,
                              style: GoogleFonts.montserrat(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _items[_index].description,
                            style: GoogleFonts.montserrat(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ----- Page indicator -----
                    Row(
                      children: List.generate(_items.length, (i) {
                        final active = i == _index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),

                    // ----- Action button -----
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.dark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                              )
                            : Text(
                                _isLastPage ? 'Get Started' : 'Next',
                                style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600),
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

/// One full-bleed photo page: the realistic agricultural background, a
/// gradient scrim for text contrast, and the small brand mark — the title/
/// description/indicator/button chrome above lives outside this widget so
/// it can animate independently of the page swipe.
class _OnboardPageView extends StatelessWidget {
  final _OnboardingItem item;
  const _OnboardPageView({required this.item});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ----- Full-bleed realistic photo, never stretched -----
        Image.asset(item.image, fit: BoxFit.cover),

        // ----- Dark green/black gradient: transparent near the top so the -----
        // ----- photo stays visible, solid enough by the bottom for white -----
        // ----- text to stay readable without needing per-letter shadows. -----
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.42, 0.72, 1.0],
              colors: [
                Colors.transparent,
                Colors.transparent,
                Color(0xCC0B2210),
                Color(0xF20B2210),
              ],
            ),
          ),
        ),

        // ----- Brand mark, upper-middle. No background — just the logo. -----
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 44),
              child: Image.asset(
                'assets/images/logo.png',
                height: 150,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.eco, size: 84, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
