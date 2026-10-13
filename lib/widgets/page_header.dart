import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The header of every main tab, for both roles — Market / Explore,
/// Messages, Orders, Profile — in two rows: the AgriTrade+ logo mark on
/// the left with the tab's own action on the right where it has one (the
/// notification bell on Market / Explore, the menu on Messages, …), then
/// the tab's title underneath. One widget, so the tabs cannot drift apart
/// in height, padding, logo size, font or colour. No "AgriTrade+"
/// wordmark — the logo stands for it.
///
/// It sits straight under the status bar: the role shells have no app
/// bar, and wrap their tabs in a SafeArea.
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

  /// The dark green of the title, and of an icon placed beside it.
  static const Color titleColor = Color(0xFF003B1F);

  // The size the logo's artwork appears at. logo.png is 612x408 with the
  // artwork taking only the middle 330x310 of it — the rest is transparent
  // margin — so fitting the whole file into a small square would leave the
  // mark looking tiny. The file is drawn larger instead, sized so the
  // artwork itself comes out [_logoSize] wide, with the transparent margin
  // allowed to spill past the layout box (it draws nothing).
  static const double _logoSize = 30;
  static const double _assetWidth = 612;
  static const double _assetHeight = 408;
  static const double _artworkWidth = 330;

  @override
  Widget build(BuildContext context) {
    const scale = _logoSize / _artworkWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_horizontalPadding, 2, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: the logo on the left, the tab's action on the right.
          // Fixed height, so the logo and the title under it sit in the
          // same place whether or not the tab has an action.
          SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // The original asset drawn as it is: no circle,
                // background or border around it, never cropped.
                ExcludeSemantics(
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
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          // Row 2: the title, on the logo's left edge.
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8, bottom: 4),
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
      ),
    );
  }
}
