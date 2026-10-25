import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'agritrade_text.dart';
import 'docked_nav_bar.dart';
import 'notification_bell.dart';

/// The header of every main tab, for both roles — Market / Explore,
/// Messages, Orders, Profile — in two rows: the AgriTrade+ logo mark on
/// the left with the tab's own action on the right where it has one (the
/// notification bell on Market / Explore, the menu on Messages, …), then
/// the tab's title underneath. One widget, so the tabs cannot drift apart
/// in height, padding, logo size, font or colour.
///
/// Only the logo row is on a band: designed like the bottom bar
/// (DockedNavBar) — pure white, its rounded corners (at the bottom) and its
/// soft shadow — but attached to the top edge, not floating. It holds the
/// logo (on no background of its own), the dark green
/// "AgriTrade+" wordmark and dark green icons. The title stays below it on
/// the page, in dark green. The band sits straight under the status bar,
/// which [PageHeaderSafeArea] paints the same colour: the role shells have
/// no app bar.
class PageHeader extends StatelessWidget {
  final String title;

  /// Optional action at the right end of the logo row.
  final Widget? trailing;

  /// Optional action on the title's own row, right-aligned and centered
  /// on the title (the farmer's Inventory button on Orders).
  final Widget? titleTrailing;

  /// False leaves the title row out: a tab whose title scrolls with its
  /// content puts a [PageTitle] at the top of its scrolling page instead,
  /// under this fixed band (Market, Profile).
  final bool includeTitle;

  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.titleTrailing,
    this.includeTitle = true,
  });

  static const double _horizontalPadding = 16;

  /// The band's colour — the bottom bar's pure white.
  static const Color background = DockedNavBar.color;

  /// The colour of an icon on the band ([trailing] — the notification
  /// bell): dark green on the light band.
  static const Color onBandColor = AppTheme.dark;

  /// The dark green of the title, and of an icon placed beside it
  /// ([titleTrailing] — the menus).
  static const Color titleColor = AppTheme.dark;

  // The size the logo's artwork appears at. logo.png is 612x408 with the
  // artwork taking only the middle 330x310 of it — the rest is transparent
  // margin — so fitting the whole file into a small square would leave the
  // mark looking tiny. The file is drawn larger instead, sized so the
  // artwork itself comes out [_logoSize] wide, with the transparent margin
  // allowed to spill past the layout box (it draws nothing).
  static const double _logoSize = 30;
  static const double _discSize = 34;
  static const double _assetWidth = 612;
  static const double _assetHeight = 408;
  static const double _artworkWidth = 330;

  @override
  Widget build(BuildContext context) {
    const scale = _logoSize / _artworkWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1, on the band: the logo and wordmark on the left, the
        // tab's action on the right. Fixed height, so the title under it
        // sits in the same place whether or not the tab has an action.
        // The shadow is kept to below the band: above, it would shade the
        // white status bar strip it joins.
        ClipRect(
          clipper: const _BelowOnly(),
          child: Container(
            width: double.infinity,
            height: 56,
            padding: const EdgeInsets.fromLTRB(_horizontalPadding, 0, 8, 4),
            // The bottom bar's look (white, its corners, its soft shadow), but
            // attached to the top edge rather than floating.
            decoration: BoxDecoration(
              color: background,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(DockedNavBar.cornerRadius),
              ),
              boxShadow: DockedNavBar.shadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The logo itself, straight on the band. Logo and wordmark
                // together go home (see HomeLogoAction).
                _HomeLogoTap(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: _discSize,
                          height: _discSize,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: _logoSize,
                            height: _logoSize,
                            child: OverflowBox(
                              maxWidth: _assetWidth * scale,
                              maxHeight: _assetHeight * scale,
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: _assetWidth * scale,
                                height: _assetHeight * scale,
                                fit: BoxFit.contain,
                                // Smooth, sharp scaling of the large artwork
                                // down to header size.
                                filterQuality: FilterQuality.high,
                                errorBuilder: (c, e, s) => const Icon(
                                  Icons.agriculture,
                                  color: AppTheme.dark,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      const AgriTradeText(fontSize: 17),
                    ],
                  ),
                ),
                const Spacer(),
                // The tab's own action, or else the notification bell the
                // role shell provides (see HomeLogoAction), so every tab has
                // the bell.
                ?(trailing ?? _shellBell(context)),
              ],
            ),
          ),
        ),
        // Row 2, on the page: the title, on the logo's left edge.
        if (includeTitle) PageTitle(title: title, trailing: titleTrailing),
      ],
    );
  }
}

// Clips to the band and everything below it (where its shadow falls), but
// nothing above.
class _BelowOnly extends CustomClipper<Rect> {
  const _BelowOnly();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-40, 0, size.width + 40, size.height + 40);

  @override
  bool shouldReclip(_BelowOnly oldClipper) => false;
}

/// Where the header's logo goes when tapped: the role's home tab — Market
/// for a farmer, Explore for a buyer. Each role shell puts one above its
/// tabs; without one the logo is not tappable.
class HomeLogoAction extends InheritedWidget {
  final VoidCallback onTap;

  /// Opens Notifications — the bell every tab's header shows when the tab
  /// has no action of its own there.
  final VoidCallback? onNotifications;

  const HomeLogoAction({
    super.key,
    required this.onTap,
    this.onNotifications,
    required super.child,
  });

  // Read when used, so a new callback on every rebuild of the shell never
  // rebuilds the tabs under it.
  static VoidCallback? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeLogoAction>()?.onTap;

  static VoidCallback? _notificationsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeLogoAction>()?.onNotifications;

  @override
  bool updateShouldNotify(HomeLogoAction oldWidget) => false;
}

class _HomeLogoTap extends StatelessWidget {
  final Widget child;
  const _HomeLogoTap({required this.child});

  @override
  Widget build(BuildContext context) {
    if (HomeLogoAction._of(context) == null) return child;
    return Semantics(
      button: true,
      label: 'AgriTrade+ home',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => HomeLogoAction._of(context)?.call(),
        child: child,
      ),
    );
  }
}

/// A main tab's title row — "Market", "Profile" — in the brand's dark
/// green, with an optional action at its right end. Part of [PageHeader];
/// on its own at the top of a tab's scrolling page, it scrolls away with
/// the content while the band above stays.
class PageTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PageHeader._horizontalPadding,
        12,
        8,
        4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Montserrat SemiBold in the brand's dark green.
              style: AppTheme.heading(22).copyWith(
                fontWeight: FontWeight.w600,
                color: PageHeader.titleColor,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// The shell's notification bell for a tab header, or null without one.
Widget? _shellBell(BuildContext context) {
  if (HomeLogoAction._notificationsOf(context) == null) return null;
  return NotificationBell(
    onPressed: () => HomeLogoAction._notificationsOf(context)?.call(),
    color: PageHeader.onBandColor,
  );
}

/// The role shells' replacement for a top [SafeArea]: the strip under the
/// phone's status bar is painted in [PageHeader.background], so it runs
/// on into each tab's header, and the status bar icons turn dark to stay
/// readable on it. [child] is laid out below the strip.
class PageHeaderSafeArea extends StatelessWidget {
  final Widget child;

  const PageHeaderSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Column(
        children: [
          Container(
            height: MediaQuery.paddingOf(context).top,
            color: PageHeader.background,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
