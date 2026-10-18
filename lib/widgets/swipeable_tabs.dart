import 'package:flutter/material.dart';

/// A home screen's bottom-navigation tabs as pages that can also be
/// swiped left and right. [index] is the tab shown — set it to go to a tab
/// (a neighbouring one slides in; a farther one is switched to directly);
/// a swipe reports the new tab through [onIndexChanged]. Every tab keeps
/// its state (scroll position, loaded data) while another is showing, as
/// an IndexedStack would.
///
/// A tab with its own horizontal swiping inside (the Orders status tabs)
/// keeps it: a swipe there moves within that tab.
class SwipeableTabs extends StatefulWidget {
  final int index;
  final ValueChanged<int> onIndexChanged;
  final List<Widget> children;

  const SwipeableTabs({
    super.key,
    required this.index,
    required this.onIndexChanged,
    required this.children,
  });

  @override
  State<SwipeableTabs> createState() => _SwipeableTabsState();
}

class _SwipeableTabsState extends State<SwipeableTabs> {
  late final PageController _controller = PageController(
    initialPage: widget.index,
  );

  // The page a swipe (or a slide this widget started) last landed on.
  late int _page = widget.index;

  @override
  void didUpdateWidget(SwipeableTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.index;
    if (target == _page || !_controller.hasClients) return;
    // Set from outside (a tap on the bar, the back button, a link).
    final distance = (target - _page).abs();
    _page = target;
    if (distance == 1) {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      onPageChanged: (page) {
        if (page == _page) return;
        _page = page;
        widget.onIndexChanged(page);
      },
      children: [for (final child in widget.children) _KeepAlive(child: child)],
    );
  }
}

/// Keeps a tab alive while it is off screen.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
