import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/login_hero.dart' show BrandHeadline, BrandLockup;
import '../widgets/login_form_fields.dart';
import 'forgot_password_screen.dart';

/// The Admin Portal's (web) login page: a full-height farm photo with the
/// AgriTrade+ lockup on the left, the sign-in form on the right. Below
/// [splitBreakpoint] it collapses to one column — a compact photo banner
/// over the form.
///
/// Layout only — the form itself, and the whole sign-in / role-check flow
/// behind it, is the shared [LoginFormFields] (role: 'admin'). Shown by
/// [LoginScreen] whenever its role is 'admin'.
class AdminLoginView extends StatefulWidget {
  final String? flashMessage;
  const AdminLoginView({super.key, this.flashMessage});

  static const splitBreakpoint = 900.0;
  // Warm off-white, so the white fields read as fields without a card.
  static const panelColor = Color(0xFFFAF9F5);

  @override
  State<AdminLoginView> createState() => _AdminLoginViewState();
}

class _AdminLoginViewState extends State<AdminLoginView> {
  // Keeps what was typed when the window is resized across the breakpoint.
  final _fieldsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return AdminAuthShell(
      loginBuilder: (context, narrow, openForgotPassword) => _FormPanel(
        flashMessage: widget.flashMessage,
        narrow: narrow,
        fieldsKey: _fieldsKey,
        onForgotPassword: openForgotPassword,
      ),
    );
  }
}

/// The page the Admin sign-in form and the Forgot Password form share:
/// the brand panel (photo, logo, tagline) and the off-white form area.
///
/// The two forms are not separate pages. Going between them changes only
/// what is in the form area — a short fade with a slight sideways slide —
/// so the photo and branding are never rebuilt, reloaded or moved. The
/// sign-in form stays alive underneath while Forgot Password is showing,
/// so what was typed in it is still there on the way back.
class AdminAuthShell extends StatefulWidget {
  /// Builds the sign-in form. [narrow] is the single-column layout, where
  /// the page scrolls and the form takes just the height it needs; call
  /// [openForgotPassword] with the email typed so far.
  final Widget Function(
    BuildContext context,
    bool narrow,
    ValueChanged<String> openForgotPassword,
  )
  loginBuilder;

  const AdminAuthShell({super.key, required this.loginBuilder});

  /// How long the form change takes, and how far the forms slide.
  static const transitionDuration = Duration(milliseconds: 250);
  static const double slideDistance = 14;

  @override
  State<AdminAuthShell> createState() => _AdminAuthShellState();
}

class _AdminAuthShellState extends State<AdminAuthShell>
    with SingleTickerProviderStateMixin {
  // 0 = sign-in form, 1 = Forgot Password.
  late final _controller = AnimationController(
    vsync: this,
    duration: AdminAuthShell.transitionDuration,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  // Non-null while the Forgot Password form exists. A new key each time it
  // is opened, so it always starts fresh; the key also carries its state
  // across a resize past the breakpoint.
  GlobalKey? _forgotKey;
  String _forgotEmail = '';
  bool _showingForgot = false;

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openForgotPassword(String email) {
    if (_showingForgot) return;
    setState(() {
      _forgotKey = GlobalKey();
      _forgotEmail = email;
      _showingForgot = true;
    });
    _controller.forward();
  }

  void _backToSignIn() {
    if (!_showingForgot) return;
    setState(() => _showingForgot = false);
    _controller.reverse().whenCompleteOrCancel(() {
      // Gone once it has faded out — unless it was opened again meanwhile.
      if (mounted && !_showingForgot && _controller.isDismissed) {
        setState(() => _forgotKey = null);
      }
    });
  }

  // One of the two forms, faded and nudged sideways by the transition.
  // The widget tree around [child] never changes shape, so its state is
  // kept; a form that is fully hidden is not laid out or hit-tested, and
  // the sign-in form cannot take the keyboard while it is covered.
  Widget _animated({required bool isLogin, required Widget child}) {
    return AnimatedBuilder(
      animation: _progress,
      child: child,
      builder: (context, child) {
        final t = _progress.value;
        final shown = isLogin ? 1 - t : t;
        final dx = AdminAuthShell.slideDistance * (isLogin ? -t : 1 - t);
        return Offstage(
          offstage: shown == 0,
          child: IgnorePointer(
            ignoring: isLogin ? _showingForgot || t > 0 : !_showingForgot,
            child: ExcludeFocus(
              excluding: isLogin && (_showingForgot || t > 0),
              child: Opacity(
                opacity: shown,
                child: Transform.translate(offset: Offset(dx, 0), child: child),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _forms(BuildContext context, bool narrow) {
    return Stack(
      // Narrow: the forms take the page's width and their own height.
      // Wide: both fill the form area and centre themselves in it.
      fit: narrow ? StackFit.passthrough : StackFit.expand,
      alignment: Alignment.topCenter,
      children: [
        _animated(
          isLogin: true,
          child: widget.loginBuilder(context, narrow, _openForgotPassword),
        ),
        if (_forgotKey != null)
          _animated(
            isLogin: false,
            child: ForgotPasswordScreen(
              key: _forgotKey,
              isAdmin: true,
              narrow: narrow,
              initialEmail: _forgotEmail,
              onBack: _backToSignIn,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminLoginView.panelColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AdminLoginView.splitBreakpoint) {
            return Row(
              children: [
                const Expanded(flex: 11, child: AdminBrandPanel()),
                Expanded(flex: 9, child: _forms(context, false)),
              ],
            );
          }
          // Narrow browser: the photo becomes a banner over the form, and
          // stays put while the form under it changes.
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 190, child: AdminBrandPanel.compact()),
                _forms(context, true),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Farm photo + dark-green tint + the brand lockup. [compact] is the
/// short banner used on narrow screens: lockup only, centred. Shared with
/// the Admin Forgot Password page, so the two can never drift apart.
class AdminBrandPanel extends StatelessWidget {
  final bool compact;
  const AdminBrandPanel({super.key}) : compact = false;
  const AdminBrandPanel.compact({super.key}) : compact = true;

  // Brighter than AppTheme.mid, which disappears against the dark tint.
  static const _accent = Color(0xFF7BD389);
  static const _textShadow = [
    Shadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/bg_adminside.png',
          fit: BoxFit.cover,
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
        // As on the mobile login: a little deeper along the top, behind the
        // lockup, nearly clear in the middle so the photo shows, and a soft
        // shade from the lower left behind the headline.
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
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1, 0.9),
              radius: 1.15,
              colors: [Color(0x990E3210), Color(0x000E3210)],
            ),
          ),
        ),
        DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white, shadows: _textShadow),
          child: compact ? _compactLayout() : _fullLayout(),
        ),
      ],
    );
  }

  // "Administrative Portal", with a small green dot, above the headline.
  Widget _portalLabel(double fontSize) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: fontSize * 0.55,
        height: fontSize * 0.55,
        decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
      ),
      SizedBox(width: fontSize * 0.75),
      Text(
        'Administrative Portal',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    ],
  );

  // The mobile login's layout, sized up: the lockup in the upper-left
  // corner, and the typed-out headline at the lower left — sized to the
  // room the window leaves it.
  Widget _fullLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: BrandLockup(scale: 1.45),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // The label above it takes about 40 px.
                final size = [
                  46.0,
                  box.maxWidth * 0.085,
                  (box.maxHeight - 40) / BrandHeadline.heightFactor,
                ].reduce((a, b) => a < b ? a : b);
                return Offstage(
                  offstage: size < 16,
                  // Shrinks, keeping its lines, rather than ever spill out
                  // on a short window.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(
                      width: box.maxWidth < 560 ? box.maxWidth : 560,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _portalLabel(13),
                          const SizedBox(height: 16),
                          BrandHeadline(
                            fontSize: size < 16 ? 16 : size,
                            shadows: _textShadow,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // The banner over the form on a narrow window: the same, smaller — the
  // lockup in the corner, the portal label and the headline under it.
  Widget _compactLayout() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: BrandLockup(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = [
                    22.0,
                    box.maxWidth * 0.065,
                    (box.maxHeight - 28) / BrandHeadline.heightFactor,
                  ].reduce((a, b) => a < b ? a : b);
                  // Shrinks, keeping its lines, rather than ever spill out
                  // of the banner on a very narrow or short window.
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _portalLabel(11.5),
                          // Too short for the headline: the label alone.
                          if (size >= 13) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: BrandHeadline(
                                fontSize: size,
                                shadows: _textShadow,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sign-in column: heading + [LoginFormFields], centred in whatever
/// space it gets and scrollable when that space is too short. With
/// [narrow] the page around it does the scrolling (see AdminAuthShell).
class _FormPanel extends StatelessWidget {
  final String? flashMessage;
  final bool narrow;
  final Key fieldsKey;
  final ValueChanged<String> onForgotPassword;
  const _FormPanel({
    required this.narrow,
    required this.fieldsKey,
    required this.onForgotPassword,
    this.flashMessage,
  });

  @override
  Widget build(BuildContext context) {
    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 24 : 40,
            vertical: narrow ? 32 : 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ADMIN PORTAL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppTheme.mid,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Welcome',
                style: TextStyle(
                  fontSize: 32,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Log in to your AgriTrade+ Admin account',
                style: TextStyle(fontSize: 14.5, color: Color(0xFF6B7468)),
              ),
              if (flashMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppTheme.dark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          flashMessage!,
                          style: AppTheme.body(size: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              LoginFormFields(
                key: fieldsKey,
                role: 'admin',
                onForgotPassword: onForgotPassword,
              ),
            ],
          ),
        ),
      ),
    );

    if (narrow) return form;
    return LayoutBuilder(
      // minHeight = the panel's own height, so the form sits in the
      // vertical centre until the window is too short, then scrolls.
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: form,
        ),
      ),
    );
  }
}
