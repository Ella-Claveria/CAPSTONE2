import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'app_back_button.dart';

/// The header of every inner screen (anything opened on top of the main
/// tabs — the tabs themselves use PageHeader). One widget, so the screens
/// cannot drift apart: the same dark green band as the tabs' header, with
/// rounded bottom corners, a white title and white icons, the same height,
/// Back button and title position. The status bar above it is the same
/// green.
///
/// It gets out of the way while reading: scrolling down the page slides
/// the bar up out of sight (the green status bar strip stays), and any
/// scroll back up — or reaching the top — brings it back. Screens whose
/// header is a field or a person ([titleWidget]: search, chats) keep it
/// in place; [hideOnScroll] overrides either way.
///
/// Only the look lives here. Pass [onBack] where a screen has its own Back
/// behaviour; otherwise Back pops the route, exactly as a plain AppBar's
/// Back button does.
class AgriAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// The screen's title. Ignored when [titleWidget] is given.
  final String? title;

  /// A custom title area — a search field, or an avatar with a name on
  /// conversation screens. It starts at the same place a text title does.
  final Widget? titleWidget;

  final List<Widget>? actions;

  /// Replaces the default "pop this route".
  final VoidCallback? onBack;

  /// False greys out Back while a screen is busy.
  final bool backEnabled;

  final String backTooltip;

  /// Whether to show Back. Defaults to showing it whenever there is a
  /// screen to go back to (or [onBack] is given).
  final bool? showBack;

  /// Whether scrolling down hides the bar. Defaults to true for a text
  /// [title], false for a [titleWidget].
  final bool? hideOnScroll;

  const AgriAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.onBack,
    this.backEnabled = true,
    this.backTooltip = 'Back',
    this.showBack,
    this.hideOnScroll,
  });

  /// The band's colour — the brand's dark green, as on the tabs' header.
  static const Color background = AppTheme.dark;

  /// Title and icons on the band.
  static const Color foreground = Colors.white;

  static const double height = 60;

  /// The title style, for a [titleWidget] that shows a name of its own.
  static TextStyle titleStyle({double size = 18}) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.bold,
    color: foreground,
  );

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<AgriAppBar> createState() => _AgriAppBarState();
}

class _AgriAppBarState extends State<AgriAppBar> {
  static const Duration _slide = Duration(milliseconds: 220);
  static const BorderRadius _corners = BorderRadius.vertical(
    bottom: Radius.circular(20),
  );

  ScrollNotificationObserverState? _observer;
  bool _hidden = false;

  bool get _hides => widget.hideOnScroll ?? widget.titleWidget == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The enclosing Scaffold passes on its body's scroll notifications
    // (the same signal a Material AppBar uses), so a screen does not hand
    // its scroll controller to the bar.
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
    if (!_hides) return;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return;
    bool? hide;
    if (notification is UserScrollNotification) {
      // Only a page long enough to scroll well past the bar hides it, so
      // a short page does not jump as the bar comes and goes.
      final longPage = metrics.maxScrollExtent > AgriAppBar.height * 2;
      if (notification.direction == ScrollDirection.reverse && longPage) {
        hide = true;
      } else if (notification.direction == ScrollDirection.forward) {
        hide = false;
      }
    }
    if (notification is ScrollUpdateNotification && metrics.extentBefore <= 0) {
      hide = false; // Back at the top.
    }
    if (hide != null && hide != _hidden && mounted) {
      setState(() => _hidden = hide!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBack =
        widget.showBack ??
        (widget.onBack != null ||
            (ModalRoute.of(context)?.impliesAppBarDismissal ?? false));

    final bar = AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AgriAppBar.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AgriAppBar.height,
      // Status bar padding is drawn by the strip above, not here.
      primary: false,
      iconTheme: const IconThemeData(color: AgriAppBar.foreground, size: 24),
      actionsIconTheme: const IconThemeData(
        color: AgriAppBar.foreground,
        size: 24,
      ),
      automaticallyImplyLeading: false,
      // The 40px circle sits 12px from the screen edge; the title starts
      // 12px after it (or at the 16px page edge when there is no Back).
      leadingWidth: 60,
      leading: hasBack
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const AppBackIcon(),
                tooltip: widget.backTooltip,
                onPressed: widget.backEnabled
                    ? (widget.onBack ?? () => Navigator.of(context).maybePop())
                    : null,
              ),
            )
          : null,
      titleSpacing: hasBack ? 4 : 16,
      centerTitle: false,
      titleTextStyle: AgriAppBar.titleStyle(),
      title:
          widget.titleWidget ??
          (widget.title == null
              ? null
              : Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
      actions: [...?widget.actions, const SizedBox(width: 4)],
    );

    // Light status bar icons on the green, whether or not the bar itself
    // is showing.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AgriAppBar.background,
            child: SizedBox(height: MediaQuery.paddingOf(context).top),
          ),
          // Slides up behind the status bar strip when hidden; the page
          // below follows the bar's height, so it gains the room.
          ClipRect(
            child: AnimatedAlign(
              duration: _slide,
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              heightFactor: _hidden ? 0 : 1,
              child: Material(
                color: AgriAppBar.background,
                shape: const RoundedRectangleBorder(borderRadius: _corners),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(height: AgriAppBar.height, child: bar),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
