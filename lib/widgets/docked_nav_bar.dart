import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The bottom navigation bar of the Farmer and Buyer home screens: the same
/// soft white bar and items as before, but docked to the bottom edge, full
/// width, the way Android bars sit, instead of a pill floating above the
/// edge. Only its top corners are rounded. Its colour carries on under the
/// phone's own navigation (gesture bar or buttons), so nothing shows
/// through below it.
///
/// With [hidden] it slides down out of sight (and fades), giving the page
/// the room — see [NavBarAutoHide], which hides it while a long page is
/// scrolled down.
class DockedNavBar extends StatelessWidget {
  /// The bar's items, laid out in a [Row]; each is usually [Expanded].
  final List<Widget> children;

  final bool hidden;

  /// Height of the item row, not counting the phone's navigation area.
  static const double height = 64;

  static const Duration slide = Duration(milliseconds: 220);

  const DockedNavBar({super.key, required this.children, this.hidden = false});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8EB99A).withValues(alpha: 0.22),
            blurRadius: 20,
            spreadRadius: 1,
            // Cast upward, onto the page above the bar.
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(children: children),
        ),
      ),
    );
    // Shrinking the height from the top lets the bar slip below the screen
    // edge (and the page grow into the room); the fade also hides anything
    // that rises above the bar, like the farmer's + button.
    return IgnorePointer(
      ignoring: hidden,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: hidden ? 0 : 1),
        duration: slide,
        curve: Curves.easeOutCubic,
        builder: (context, shown, child) => Opacity(
          opacity: shown,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: shown,
            child: child,
          ),
        ),
        child: bar,
      ),
    );
  }
}

/// Watches the tab pages' vertical scrolling and decides when the bottom
/// bar hides: scrolling down a page long enough to scroll well past it
/// hides it; any scroll back up, or reaching the top, shows it again.
/// Sideways swipes (between tabs) are ignored.
class NavBarAutoHide extends StatelessWidget {
  final Widget child;
  final ValueChanged<bool> onHiddenChanged;

  const NavBarAutoHide({
    super.key,
    required this.child,
    required this.onHiddenChanged,
  });

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is UserScrollNotification) {
      final longPage = metrics.maxScrollExtent > DockedNavBar.height * 2;
      if (notification.direction == ScrollDirection.reverse && longPage) {
        onHiddenChanged(true);
      } else if (notification.direction == ScrollDirection.forward) {
        onHiddenChanged(false);
      }
    } else if (notification is ScrollUpdateNotification &&
        metrics.extentBefore <= 0) {
      onHiddenChanged(false); // Back at the top.
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: child,
      );
}
