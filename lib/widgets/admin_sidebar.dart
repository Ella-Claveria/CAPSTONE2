import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'agritrade_text.dart';

/// One page in the Admin Portal's navigation. A page with several views of
/// its own lists them as [children], which the sidebar shows as a
/// collapsible submenu under it.
class AdminSidebarEntry {
  final IconData icon;
  final String label;
  final List<String> children;
  const AdminSidebarEntry(this.icon, this.label, {this.children = const []});
}

/// The Admin Portal's navigation: a dark green column with the AgriTrade+
/// logo and wordmark on top and the pages under it, one item each. A page
/// with [AdminSidebarEntry.children] has a small chevron and a submenu.
///
/// The same widget is the full sidebar on a desktop window, the icon-only
/// rail on a tablet-sized one ([collapsed]) and the contents of the
/// navigation drawer on a phone-sized one — so the three can never list
/// different pages. The rail has no room for submenus: its icons open the
/// page, whose own tabs then do the rest.
class AdminSidebar extends StatefulWidget {
  final List<AdminSidebarEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Which child of the selected entry is open, if it has children.
  final int? selectedChildIndex;

  /// A submenu item was chosen: the entry's index, then the child's.
  final void Function(int index, int childIndex)? onSelectChild;

  /// Pinned at the bottom under a thin divider (the Admin account). It
  /// stays put while the pages above it scroll.
  final Widget? footer;

  /// Icon-only rail: labels become tooltips.
  final bool collapsed;

  const AdminSidebar({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onSelect,
    this.selectedChildIndex,
    this.onSelectChild,
    this.footer,
    this.collapsed = false,
  });

  // The app's main dark green, the same as the portal's buttons.
  static const Color background = AppTheme.dark;
  // The active page: a cream tab growing out of the sidebar's left edge,
  // with the sidebar's own green for its icon and text.
  static const Color activeBackground = Color(0xFFF2F3E9);
  static const Color activeForeground = background;
  static const double expandedWidth = 248;
  static const double collapsedWidth = 72;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  // The entries whose submenu is open. The open page's own starts open.
  late final Set<int> _expanded = {widget.selectedIndex};

  @override
  void didUpdateWidget(AdminSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Going to a page (from anywhere) opens its submenu.
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _expanded.add(widget.selectedIndex);
    }
  }

  void _toggle(int index) => setState(() {
    if (!_expanded.remove(index)) _expanded.add(index);
  });

  // The parent row itself: opens its page, or — already there — folds its
  // submenu away or back out.
  void _onParentTap(int index) {
    if (index == widget.selectedIndex) {
      _toggle(index);
    } else {
      setState(() => _expanded.add(index));
      widget.onSelect(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final entries = widget.entries;
    return Material(
      color: AdminSidebar.background,
      child: SizedBox(
        width: collapsed
            ? AdminSidebar.collapsedWidth
            : AdminSidebar.expandedWidth,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _brand(),
              // The pages scroll on their own if the window is too short
              // for them; the brand above stays put.
              Expanded(
                child: SingleChildScrollView(
                  // Nothing on the left: the active tab is flush with the
                  // sidebar's edge.
                  padding: EdgeInsets.fromLTRB(0, 4, collapsed ? 12 : 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < entries.length; i++) ..._entry(i),
                    ],
                  ),
                ),
              ),
              if (widget.footer != null) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: collapsed ? 12 : 14,
                  endIndent: collapsed ? 12 : 14,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                widget.footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _entry(int i) {
    final entry = widget.entries[i];
    final selected = i == widget.selectedIndex;
    final hasChildren = entry.children.isNotEmpty && !widget.collapsed;
    if (!hasChildren) {
      return [
        _AdminSidebarItem(
          icon: entry.icon,
          label: entry.label,
          selected: selected,
          collapsed: widget.collapsed,
          onTap: () => widget.onSelect(i),
        ),
      ];
    }

    final open = _expanded.contains(i);
    return [
      _AdminSidebarItem(
        icon: entry.icon,
        label: entry.label,
        selected: selected,
        collapsed: false,
        expanded: open,
        onTap: () => _onParentTap(i),
        // The chevron on its own only folds the submenu, without leaving
        // the current page.
        onToggle: () => _toggle(i),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: open
            ? Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < entry.children.length; j++)
                      _AdminSidebarSubItem(
                        label: entry.children[j],
                        selected: selected && j == widget.selectedChildIndex,
                        onTap: () => widget.onSelectChild?.call(i, j),
                      ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    ];
  }

  // The original logo asset and the app's own wordmark widget, in its
  // white on-dark version.
  Widget _brand() {
    final collapsed = widget.collapsed;
    final logo = Image.asset(
      'assets/images/logo.png',
      height: 38,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.agriculture_rounded, color: Colors.white, size: 28),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 0 : 14,
        20,
        collapsed ? 0 : 14,
        18,
      ),
      child: collapsed
          ? Center(child: logo)
          : Row(
              children: [
                logo,
                const SizedBox(width: 4),
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AgriTradeText(fontSize: 21, light: true),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One row of the sidebar. Transparent until hovered or selected; the
/// selected page becomes a cream tab attached to the sidebar's left edge,
/// rounded on the right. Both fade over 160 ms.
///
/// With [onToggle], the row is a submenu's parent: it ends in a small
/// chevron that points down while the submenu is [expanded].
class _AdminSidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final bool expanded;

  const _AdminSidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    this.onTap,
    this.onToggle,
    this.expanded = false,
  });

  @override
  State<_AdminSidebarItem> createState() => _AdminSidebarItemState();
}

class _AdminSidebarItemState extends State<_AdminSidebarItem> {
  bool _hovered = false;

  static const double _height = 44;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AdminSidebar.activeForeground
        : Colors.white.withValues(alpha: _hovered ? 0.95 : 0.78);

    final Widget content = widget.collapsed
        ? Center(
            child: Icon(widget.icon, size: _iconSize, color: color),
          )
        : Row(
            children: [
              Icon(widget.icon, size: _iconSize, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              if (widget.onToggle != null)
                Semantics(
                  button: true,
                  label: widget.expanded
                      ? 'Collapse ${widget.label}'
                      : 'Expand ${widget.label}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: AnimatedRotation(
                        turns: widget.expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

    Widget item = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: _height,
            // The row touches the sidebar's left edge, so the inset that
            // lines the icons up with the logo is inside it. On the rail
            // the inset keeps the icon centred under the logo.
            padding: widget.collapsed
                ? const EdgeInsets.only(left: 12)
                : EdgeInsets.only(
                    left: 26,
                    right: widget.onToggle != null ? 6 : 12,
                  ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AdminSidebar.activeBackground
                  : Colors.white.withValues(alpha: _hovered ? 0.08 : 0),
              // Square against the edge, rounded on the right only.
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(18),
              ),
            ),
            child: content,
          ),
        ),
      ),
    );

    // A submenu's parent keeps its chevron reachable on its own.
    if (widget.onToggle == null) {
      item = Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: item,
      );
    }
    // On the rail the label is only a tooltip.
    if (widget.collapsed) {
      item = Tooltip(message: widget.label, child: item);
    }
    return item;
  }
}

/// One submenu row: smaller text, indented to line up under its parent's
/// label. The open one is white and semi-bold on a soft highlight, with a
/// cream marker in front of it.
class _AdminSidebarSubItem extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AdminSidebarSubItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AdminSidebarSubItem> createState() => _AdminSidebarSubItemState();
}

class _AdminSidebarSubItemState extends State<_AdminSidebarSubItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 32,
            margin: const EdgeInsets.only(left: 40, bottom: 2),
            padding: const EdgeInsets.only(left: 10, right: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: selected ? 0.14 : (_hovered ? 0.07 : 0),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // The marker: cream and solid on the open view.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AdminSidebar.activeBackground
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: Colors.white.withValues(
                        alpha: selected ? 1 : (_hovered ? 0.92 : 0.72),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
