import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The look of every Back button in the app, and it follows the page's
/// scroll position by itself:
///
///  * on a dark (green) header — always just the white arrow;
///  * at the top of the page — just the arrow, nothing behind it, green on
///    a light header;
///  * once content has scrolled under the header — a white circle with a
///    very soft shadow fades in behind a green arrow, so the button stays
///    readable over whatever is passing beneath it. Scrolling back to the
///    top fades the circle out again.
///
/// The arrow itself is always there. Drawing only — it has no tap of its
/// own.
///
/// It listens to the enclosing Scaffold's scroll notifications (the same
/// signal a Material AppBar uses to know content is under it), so a screen
/// does not pass it a scroll controller. The global theme (AppTheme) uses
/// it as the icon of every app bar's Back button, AgriAppBar uses it, and
/// a screen that builds its own Back IconButton passes it as the `icon`.
class AppBackIcon extends StatefulWidget {
  /// True where the button floats over a photo: the circle then stays on
  /// at all times, since an arrow alone cannot be relied on to show up
  /// against an arbitrary image.
  final bool overImage;

  /// True inside an app bar's own band (AgriAppBar), where nothing ever
  /// scrolls under the button: just the dark green arrow, never a circle.
  final bool onBar;

  const AppBackIcon({super.key, this.overImage = false, this.onBar = false});

  static const double size = 40;

  @override
  State<AppBackIcon> createState() => _AppBackIconState();
}

class _AppBackIconState extends State<AppBackIcon> {
  static const Duration _fade = Duration(milliseconds: 200);

  ScrollNotificationObserverState? _observer;
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (identical(observer, _observer)) return;
    _observer?.removeListener(_onScroll);
    _observer = observer;
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return;
    }
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return;
    final scrolled = metrics.extentBefore > 0;
    if (scrolled != _scrolled && mounted) setState(() => _scrolled = scrolled);
  }

  @override
  Widget build(BuildContext context) {
    // Inside an app bar the surrounding icon colour is the bar's foreground
    // colour, which tells a dark header from a light one.
    final ambient = IconTheme.of(context).color;
    final onDark = ambient != null && ambient.computeLuminance() > 0.5;
    // A coloured (dark green) header already keeps the white arrow
    // readable, so the circle only comes in on a light header or over a
    // photo.
    final showCircle =
        widget.overImage || (_scrolled && !onDark && !widget.onBar);
    final arrowColor = (!showCircle && onDark)
        ? Colors.white
        : widget.onBar
        ? AppTheme.dark
        : AppTheme.mid;

    return SizedBox(
      width: AppBackIcon.size,
      height: AppBackIcon.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: showCircle ? 1 : 0,
              duration: _fade,
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: arrowColor),
            duration: _fade,
            builder: (context, color, _) =>
                Icon(Icons.arrow_back, color: color ?? arrowColor, size: 22),
          ),
        ],
      ),
    );
  }
}

/// The floating Back button for screens without an app bar: [AppBackIcon]
/// made tappable. Place it in a Stack above the scrolling content so it
/// stays put while the page scrolls.
class AppBackButton extends StatelessWidget {
  /// Defaults to popping the current route.
  final VoidCallback? onPressed;

  /// See [AppBackIcon.overImage].
  final bool overImage;

  const AppBackButton({super.key, this.onPressed, this.overImage = false});

  static const double size = AppBackIcon.size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppBackIcon(overImage: overImage),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed ?? () => Navigator.of(context).maybePop(),
              child: const Tooltip(message: 'Back', child: SizedBox.expand()),
            ),
          ),
        ),
      ],
    );
  }
}
