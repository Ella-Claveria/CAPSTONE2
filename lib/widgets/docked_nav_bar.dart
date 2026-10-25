import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bottom navigation bar of the Farmer and Buyer home screens: a small,
/// solid white pill floating a little above the bottom edge, inset from
/// the sides, on a soft shadow. It sits above the phone's own navigation
/// (gesture bar or buttons), never under it, and it stays on screen —
/// it does not hide while a page is scrolled.
class DockedNavBar extends StatelessWidget {
  /// The bar's items, laid out in a [Row]; each is usually a [NavBarItem].
  final List<Widget> children;

  /// Height of the pill itself.
  static const double height = 54;

  /// The bar's look — pure white, these corners, this shadow — which the
  /// tabs' header band (PageHeader) shares.
  static const Color color = Colors.white;
  static const double cornerRadius = 27;
  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(cornerRadius),
  );

  const DockedNavBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: _radius,
            boxShadow: shadow,
          ),
          // For the items' ripples. Not clipped: the farmer's + button
          // rises above the pill.
          child: Material(
            type: MaterialType.transparency,
            borderRadius: _radius,
            clipBehavior: Clip.none,
            child: SizedBox(
              height: height,
              child: Row(children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab in [DockedNavBar] — the same small icon and label for the Farmer
/// and the Buyer. [decorateIcon] puts a badge on the icon (the red dot
/// for unread messages or new orders).
class NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget Function(Widget icon)? decorateIcon;

  const NavBarItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.decorateIcon,
  });

  static const Color _unselected = Color(0xFFAAB4AC);

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.dark : _unselected;
    final iconWidget = Icon(
      selected ? activeIcon : icon,
      color: color,
      size: 19,
    );
    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            decorateIcon?.call(iconWidget) ?? iconWidget,
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
