import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'app_back_button.dart';

/// The header of every inner screen (anything opened on top of the main
/// tabs — the tabs themselves use PageHeader). One widget, so the screens
/// cannot drift apart: same very light green background, height, floating
/// Back button, title position, Montserrat title and icon colour, with a
/// hairline under it instead of a shadow. It is the Scaffold's app bar, so
/// it stays in place while the page scrolls and sits below the status bar.
///
/// Only the look lives here. Pass [onBack] where a screen has its own Back
/// behaviour; otherwise Back pops the route, exactly as a plain AppBar's
/// Back button does.
class AgriAppBar extends StatelessWidget implements PreferredSizeWidget {
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

  const AgriAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.onBack,
    this.backEnabled = true,
    this.backTooltip = 'Back',
    this.showBack,
  });

  static const Color background = Color(0xFFF7FAF7);
  static const Color _hairline = Color(0xFFE3EAE3);
  static const double height = 60;

  /// The title style, for a [titleWidget] that shows a name of its own.
  static TextStyle titleStyle({double size = 18}) => GoogleFonts.montserrat(
    fontSize: size,
    fontWeight: FontWeight.bold,
    color: AppTheme.dark,
  );

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final hasBack =
        showBack ??
        (onBack != null ||
            (ModalRoute.of(context)?.impliesAppBarDismissal ?? false));

    return AppBar(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppTheme.dark,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: height,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      shape: const Border(bottom: BorderSide(color: _hairline)),
      iconTheme: const IconThemeData(color: AppTheme.dark, size: 24),
      actionsIconTheme: const IconThemeData(color: AppTheme.dark, size: 24),
      automaticallyImplyLeading: false,
      // The 40px circle sits 12px from the screen edge; the title starts
      // 12px after it (or at the 16px page edge when there is no Back).
      leadingWidth: 60,
      leading: hasBack
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const AppBackIcon(),
                tooltip: backTooltip,
                onPressed: backEnabled
                    ? (onBack ?? () => Navigator.of(context).maybePop())
                    : null,
              ),
            )
          : null,
      titleSpacing: hasBack ? 4 : 16,
      centerTitle: false,
      titleTextStyle: titleStyle(),
      title:
          titleWidget ??
          (title == null
              ? null
              : Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis)),
      actions: [...?actions, const SizedBox(width: 4)],
    );
  }
}
