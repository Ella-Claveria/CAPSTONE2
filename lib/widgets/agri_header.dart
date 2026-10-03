import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'notification_bell.dart';

/// The branded top bar of both role shells (Farmer Home and Buyer
/// Marketplace), and so of every main tab inside them — Market / Explore,
/// Messages, Orders, Profile. One widget, so the two roles cannot drift
/// apart: same height, padding, logo size and bell position.
///
/// The logo is the original asset drawn straight onto the header: no
/// circle, background, border or shadow around it, never cropped, and its
/// transparent areas left as they are.
class AgriHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onNotificationsPressed;

  /// Tapping the logo (each shell uses it to return to its first tab).
  final VoidCallback? onLogoTap;

  /// Lets a shell point its first-time walkthrough at the bell.
  final Key? bellKey;

  const AgriHeader({
    super.key,
    required this.onNotificationsPressed,
    this.onLogoTap,
    this.bellKey,
  });

  static const double height = 60;
  static const double _horizontalPadding = 16;
  static const double _logoSize = 44;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/images/logo.png',
      width: _logoSize,
      height: _logoSize,
      // contain, not cover: the whole logo, never cropped.
      fit: BoxFit.contain,
      errorBuilder: (c, e, s) =>
          const Icon(Icons.agriculture, color: AppTheme.dark, size: 28),
    );

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 1,
      toolbarHeight: height,
      automaticallyImplyLeading: false,
      titleSpacing: _horizontalPadding,
      title: Align(
        alignment: Alignment.centerLeft,
        child: onLogoTap == null
            ? logo
            : Semantics(
                button: true,
                label: 'Go to the first tab',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLogoTap,
                  child: logo,
                ),
              ),
      ),
      actions: [
        NotificationBell(
          key: bellKey,
          onPressed: onNotificationsPressed,
          color: AppTheme.dark,
        ),
        // The bell's own tap area pads it; this brings its icon to the
        // same 16px edge as the logo.
        const SizedBox(width: _horizontalPadding - 8),
      ],
    );
  }
}
