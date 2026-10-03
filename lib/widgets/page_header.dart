import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The title row at the top of a main tab (Messages, Orders, Profile), so
/// they all share one font, size, weight, colour, left edge and height —
/// with or without an icon on the right.
class PageHeader extends StatelessWidget {
  final String title;

  /// Optional icon button on the same row, right-aligned (menu, inventory).
  final Widget? trailing;

  const PageHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
      // Fixed height: the title sits in the same place whether or not the
      // row has an icon.
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(22),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
