import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'agritrade_text.dart';

/// The header of every main tab, for both roles — Market / Explore,
/// Messages, Orders, Profile — in two rows: the AgriTrade+ logo mark on
/// the left with the tab's own action on the right where it has one (the
/// notification bell on Market / Explore, the menu on Messages, …), then
/// the tab's title underneath. One widget, so the tabs cannot drift apart
/// in height, padding, logo size, font or colour.
///
/// Only the logo row is on colour: a dark green band with rounded bottom
/// corners, so the tabs are not all white, holding the logo on a small
/// white disc (the green artwork alone was lost on the green), the white
/// "AgriTrade+" wordmark and white icons. The title stays below it on the
/// page, in dark green. The band sits straight under the status bar,
/// which [PageHeaderSafeArea] paints the same green: the role shells have
/// no app bar.
class PageHeader extends StatelessWidget {
  final String title;

  /// Optional action at the right end of the logo row.
  final Widget? trailing;

  /// Optional action on the title's own row, right-aligned and centered
  /// on the title (the farmer's Inventory button on Orders).
  final Widget? titleTrailing;

  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.titleTrailing,
  });

  static const double _horizontalPadding = 16;

  /// The band's colour — the brand's dark green.
  static const Color background = AppTheme.dark;

  /// The colour of an icon on the band ([trailing] — the notification
  /// bell): white on the green.
  static const Color onBandColor = Colors.white;

  /// The dark green of the title, and of an icon placed beside it
  /// ([titleTrailing] — the menus).
  static const Color titleColor = AppTheme.dark;

  // The size the logo's artwork appears at. logo.png is 612x408 with the
  // artwork taking only the middle 330x310 of it — the rest is transparent
  // margin — so fitting the whole file into a small square would leave the
  // mark looking tiny. The file is drawn larger instead, sized so the
  // artwork itself comes out [_logoSize] wide, with the transparent margin
  // allowed to spill past the layout box (it draws nothing).
  static const double _logoSize = 27;
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
        // Row 1, on the green band: the logo and wordmark on the left, the
        // tab's action on the right. Fixed height, so the title under it
        // sits in the same place whether or not the tab has an action.
        Container(
          width: double.infinity,
          height: 56,
          padding: const EdgeInsets.fromLTRB(_horizontalPadding, 0, 8, 4),
          decoration: const BoxDecoration(
            color: background,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The logo on a white disc, so its green artwork stands out
              // on the green band.
              ExcludeSemantics(
                child: Container(
                  width: _discSize,
                  height: _discSize,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
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
              const AgriTradeText(fontSize: 17, light: true),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        // Row 2, on the page: the title, on the logo's left edge.
        Padding(
          padding: const EdgeInsets.fromLTRB(_horizontalPadding, 12, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Montserrat SemiBold in the brand's dark green.
                  style: AppTheme.heading(
                    22,
                  ).copyWith(fontWeight: FontWeight.w600, color: titleColor),
                ),
              ),
              ?titleTrailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// The role shells' replacement for a top [SafeArea]: the strip under the
/// phone's status bar is painted in [PageHeader.background], so it runs
/// on into each tab's green header, and the status bar icons turn light
/// to stay readable on it. [child] is laid out below the strip.
class PageHeaderSafeArea extends StatelessWidget {
  final Widget child;

  const PageHeaderSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
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
