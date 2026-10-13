import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one search bar for product/farmer search: a white pill with a thin
/// green outline, the search icon, then the text. Marketplace shows it as a
/// button that opens the Search screen ([onTap]); the Search screen shows
/// the same bar as a real field ([controller]) — same height, radius,
/// padding, icon and type either way, so nothing shifts between the two.
///
/// Focus changes one thing only: the outline goes a darker green. Size,
/// shape, padding and fill stay as they are.
class AppSearchBar extends StatefulWidget {
  final String hint;

  /// Set to make the bar a button rather than a field.
  final VoidCallback? onTap;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shown as a clear (x) button while the field has text.
  final VoidCallback? onClear;

  final bool autofocus;

  const AppSearchBar({
    super.key,
    this.hint = 'Search crops, livestock, or farmers...',
    this.onTap,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
  });

  static const double height = 48;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  static const _textStyle = TextStyle(fontSize: 13.5, color: Colors.black87);

  // A screen that does not manage focus itself still gets the focused
  // outline: the bar then tracks focus with a node of its own.
  final FocusNode _ownFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    widget.controller?.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus).removeListener(_rebuild);
      _focus.addListener(_rebuild);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_rebuild);
      widget.controller?.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _ownFocus.dispose();
    widget.controller?.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.onTap == null && _focus.hasFocus;
    final hintStyle = _textStyle.copyWith(color: Colors.grey[500]);
    final hasText = widget.controller?.text.isNotEmpty ?? false;
    final showClear = widget.onClear != null && hasText;

    final content = Row(
      children: [
        const SizedBox(width: 16),
        const Icon(Icons.search, color: AppTheme.dark, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: widget.onTap != null
              ? Text(
                  widget.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hintStyle,
                )
              : TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  style: _textStyle,
                  cursorColor: AppTheme.dark,
                  textInputAction: TextInputAction.search,
                  // Every border off: the pill around the field is the
                  // only outline, so the app-wide focused border can't
                  // redraw the field in a different shape.
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: hintStyle,
                    hintMaxLines: 1,
                  ),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                ),
        ),
        if (showClear)
          IconButton(
            icon: Icon(Icons.close, color: Colors.grey[500], size: 18),
            onPressed: widget.onClear,
          )
        else
          const SizedBox(width: 16),
      ],
    );

    return SizedBox(
      height: AppSearchBar.height,
      child: Material(
        color: Colors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: AppTheme.dark.withValues(alpha: focused ? 0.6 : 0.25),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.onTap != null
            ? InkWell(onTap: widget.onTap, child: content)
            : content,
      ),
    );
  }
}
