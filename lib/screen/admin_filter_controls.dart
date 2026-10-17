import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_theme.dart';

// The date range picker is part of this kit.
export 'admin_date_range_dialog.dart'
    show showAdminDateRangePicker, showAdminDatePicker;
// …and so is the portal's text field.
export 'admin_field.dart';

import 'admin_dashboard_screen.dart'
    show AdminPalette, AdminRadii, AdminThemeScope;

// The Admin Portal's filter controls — one search field, one dropdown and
// one toggle, all pill-shaped, so every page's filter row looks and reads
// the same.

/// The portal's font: Montserrat from the app's own font files (see
/// pubspec.yaml), which has every weight — so a bold title is drawn with
/// the bold file. It is the Admin theme's font, and is named outright in
/// the few places that draw text with a style of their own instead of
/// inheriting the page's (table cells, dropdowns, chart tooltips).
const String kAdminFontFamily = 'Montserrat';

/// The colour of a popup's main button and its chosen option: the app's
/// dark green, or the portal's lighter green on the dark theme, where the
/// dark one would not show.
Color adminActionColor(AdminPalette c) => c.isDark ? c.green : AppTheme.dark;

/// Text and icons on [adminActionColor].
Color adminOnActionColor(AdminPalette c) =>
    c.isDark ? AppTheme.dark : Colors.white;

/// Corner radius of every menu and popup in the portal — the same rounded
/// card the mobile app's popups use.
const double kAdminPopupRadius = 20;

/// What is typed in the header's search box while a page with a table is
/// open. That page filters its rows by it — there is one search in the
/// portal, the header's, rather than one more on every page. Emptied when
/// the Admin moves to another page.
final ValueNotifier<String> adminPageSearch = ValueNotifier<String>('');

/// For a page that filters by the header's search: [pageSearch] is the
/// current text, and the page rebuilds whenever it changes.
mixin AdminPageSearch<T extends StatefulWidget> on State<T> {
  String get pageSearch => adminPageSearch.value;

  /// Runs inside the rebuild, for a page that has something to reset when
  /// the search changes (how many rows it is showing, say).
  void onPageSearchChanged() {}

  void _searchChanged() {
    if (mounted) setState(onPageSearchChanged);
  }

  @override
  void initState() {
    super.initState();
    adminPageSearch.addListener(_searchChanged);
  }

  @override
  void dispose() {
    adminPageSearch.removeListener(_searchChanged);
    super.dispose();
  }
}

/// For a popup that starts Firestore reads from its build(): each read is
/// started once and the same Future / Stream handed back on every later
/// rebuild, instead of a new read (and a flash of "loading") each time
/// the popup rebuilds.
mixin AdminReadOnce<T extends StatefulWidget> on State<T> {
  final Map<String, Object> _reads = {};

  Future<R> readOnce<R>(String key, Future<R> Function() read) =>
      (_reads[key] ??= read()) as Future<R>;

  Stream<R> watchOnce<R>(String key, Stream<R> Function() open) =>
      (_reads[key] ??= open()) as Stream<R>;
}

/// The pill-shaped field every search box and dropdown sits in.
InputDecoration adminPillDecoration(
  AdminPalette c, {
  String? hint,
  IconData? icon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminRadii.pill),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
    prefixIcon: icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Icon(icon, size: 18, color: c.textSecondary),
          ),
    prefixIconConstraints: const BoxConstraints(minHeight: 18),
    filled: true,
    fillColor: c.surfaceAlt,
    isDense: true,
    contentPadding: EdgeInsets.fromLTRB(icon == null ? 16 : 0, 12, 14, 12),
    border: border(c.border),
    enabledBorder: border(c.border),
    focusedBorder: border(c.green, 1.5),
  );
}

/// A pill-shaped search box.
class AdminPillSearch extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  const AdminPillSearch({
    super.key,
    required this.hint,
    required this.onChanged,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return SizedBox(
      width: width,
      child: TextField(
        style: TextStyle(color: c.textPrimary, fontSize: 13),
        decoration: adminPillDecoration(c, hint: hint, icon: Icons.search),
        onChanged: onChanged,
      ),
    );
  }
}

/// A pill-shaped dropdown. The chosen option always stays on one line
/// (shortened with "…" if it cannot fit) instead of wrapping and being cut
/// off. Its menu is a rounded card that opens just under the pill, so the
/// pill that was clicked stays in view while choosing.
class AdminPillDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final double width;

  const AdminPillDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.width = 200,
  });

  Future<void> _open(BuildContext context, AdminPalette c) async {
    final button = context.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return;
    // The menu's top-left corner: the pill's bottom-left, a little lower.
    final corner = button.localToGlobal(
      Offset(0, button.size.height + 6),
      ancestor: overlay,
    );
    final action = adminActionColor(c);
    // By position, not by value: a value may itself be null ("All …").
    final chosen = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        corner.dx,
        corner.dy,
        overlay.size.width - corner.dx - button.size.width,
        0,
      ),
      color: c.surface,
      constraints: BoxConstraints(
        minWidth: button.size.width,
        maxWidth: button.size.width < 320 ? 320 : button.size.width,
        maxHeight: 380,
      ),
      items: [
        for (final (i, item) in items.indexed)
          PopupMenuItem<int>(
            value: i,
            enabled: item.enabled,
            height: 44,
            textStyle: TextStyle(
              fontFamily: kAdminFontFamily,
              fontSize: 13,
              fontWeight: item.value == value
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: item.value == value ? action : c.textPrimary,
            ),
            child: item.child,
          ),
      ],
    );
    if (chosen == null) return;
    final item = items[chosen];
    item.onTap?.call();
    if (item.value != value) onChanged(item.value as T);
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    final shown = items.where((item) => item.value == value).firstOrNull;
    return SizedBox(
      width: width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context, c),
          child: InputDecorator(
            decoration: adminPillDecoration(c, icon: icon),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kAdminFontFamily,
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    child: shown?.child ?? const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped toggle between a few choices.
class AdminPillToggle<T> extends StatelessWidget {
  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  const AdminPillToggle({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AdminRadii.pill),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: option.value == value ? c.green : Colors.transparent,
                    borderRadius: BorderRadius.circular(AdminRadii.pill),
                  ),
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: option.value == value
                          ? adminOnActionColor(c)
                          : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The decoration of a text field several lines tall, in a dialog: the
/// portal's field colours with a rounded corner — a pill would crowd text
/// that runs over more than one line.
InputDecoration adminMultilineDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
}) {
  final theme = Theme.of(context).inputDecorationTheme;
  OutlineInputBorder border(InputBorder? from) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: from?.borderSide ?? const BorderSide(),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    alignLabelWithHint: true,
    border: border(theme.enabledBorder),
    enabledBorder: border(theme.enabledBorder),
    focusedBorder: border(theme.focusedBorder),
  );
}

/// [adminActionColor] from inside a dialog, where the palette is out of
/// reach: read back from the portal's button theme.
Color adminActionOf(BuildContext context) =>
    Theme.of(
      context,
    ).filledButtonTheme.style?.backgroundColor?.resolve(const {}) ??
    Theme.of(context).colorScheme.primary;

/// The portal's "loading" sign while data is being fetched: the same thin
/// moving bar the mobile app shows while a conversation's messages load
/// (see ChatMessagesLoadingBar), in the portal's dark green. Used wherever
/// a page or popup is waiting for its data.
class AdminLoadingBar extends StatelessWidget {
  final double width;
  const AdminLoadingBar({super.key, this.width = 220});

  @override
  Widget build(BuildContext context) {
    final color = adminActionOf(context);
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            minHeight: 3,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}

/// The background of every table's header row: the portal's dark green,
/// the same as its buttons, so the header is a solid band over the rows.
Color adminTableHeaderColor(AdminPalette c) => adminActionColor(c);

/// The text of every table's header row: bold, in the colour that reads
/// on the dark green band.
TextStyle adminTableHeaderStyle(AdminPalette c) => TextStyle(
  fontFamily: kAdminFontFamily,
  color: adminOnActionColor(c),
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.2,
);

// ---- Tables ----
// Every table in the portal sits in the same card (see [adminTableCard])
// with the same spacing, and is as wide as that card ([AdminTableFit]).

/// The card a table sits in: rounded corners and a thin border. The card
/// clips what is in it (`clipBehavior: Clip.antiAlias` where it is used),
/// so the dark green header band fills its whole top, edge to edge and
/// round into the corners, with no white margin around it.
///
/// [tabbed] squares the top-left corner, where [AdminTabbedTable]'s first
/// tab joins the card.
BoxDecoration adminTableCard(AdminPalette c, {bool tabbed = false}) =>
    BoxDecoration(
      color: c.surface,
      borderRadius: tabbed
          ? const BorderRadius.only(
              topRight: Radius.circular(kAdminTableRadius),
              bottomLeft: Radius.circular(kAdminTableRadius),
              bottomRight: Radius.circular(kAdminTableRadius),
            )
          : BorderRadius.circular(kAdminTableRadius),
      border: Border.all(color: c.border),
    );

/// How round a table card's corners are.
const double kAdminTableRadius = 14;

/// Rows on one page of a table.
const int kAdminRowsPerPage = 10;

/// How many pages [count] rows take; at least one.
int adminPageCount(int count, {int perPage = kAdminRowsPerPage}) =>
    count <= 0 ? 1 : (count + perPage - 1) ~/ perPage;

/// The rows of page [page] (0-based), the page clamped to those there are.
List<T> adminPageOf<T>(
  List<T> rows,
  int page, {
  int perPage = kAdminRowsPerPage,
}) {
  final last = adminPageCount(rows.length, perPage: perPage) - 1;
  final p = page.clamp(0, last);
  final start = p * perPage;
  return rows.sublist(start, (start + perPage).clamp(0, rows.length));
}

/// A table shown [kAdminRowsPerPage] rows at a time: [builder] gets the
/// rows of the open page, and the pager is under it (only when there is
/// more than one page). Back to the first page whenever [resetKey] changes
/// — a new search, filter, sort or tab.
class AdminPaged<T> extends StatefulWidget {
  final List<T> items;
  final Object? resetKey;
  final Widget Function(BuildContext context, List<T> pageItems) builder;

  const AdminPaged({
    super.key,
    required this.items,
    required this.builder,
    this.resetKey,
  });

  @override
  State<AdminPaged<T>> createState() => _AdminPagedState<T>();
}

class _AdminPagedState<T> extends State<AdminPaged<T>> {
  int _page = 0;

  @override
  void didUpdateWidget(AdminPaged<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final pages = adminPageCount(items.length);
    final page = _page.clamp(0, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.builder(context, adminPageOf(items, page)),
        if (pages > 1)
          AdminTablePager(
            page: page,
            pageCount: pages,
            total: items.length,
            onPage: (p) => setState(() => _page = p),
          ),
      ],
    );
  }
}

/// Under a table: "Showing 11–20 of 34" and ‹ 1 2 3 4 5 ›, the open page
/// a dark green square. Up to five page numbers, around the open one.
class AdminTablePager extends StatelessWidget {
  /// 0-based.
  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onPage;
  final int perPage;

  /// More rows than [total] exist, not loaded yet ("of 20+").
  final bool more;

  const AdminTablePager({
    super.key,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
    this.perPage = kAdminRowsPerPage,
    this.more = false,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
        AdminPalette.light;
    final action = adminActionColor(c);
    // Five numbers, the open page in the middle where it can be.
    var first = page - 2;
    if (first + 5 > pageCount) first = pageCount - 5;
    if (first < 0) first = 0;
    final last = (first + 5).clamp(0, pageCount);

    Widget square({
      required Widget child,
      required VoidCallback? onTap,
      bool selected = false,
      String? tooltip,
    }) {
      final box = Material(
        color: selected ? action : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: selected ? action : c.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 32, height: 32, child: Center(child: child)),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: tooltip == null ? box : Tooltip(message: tooltip, child: box),
      );
    }

    final from = page * perPage + 1;
    final to = ((page + 1) * perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Text(
            'Showing $from–$to of $total${more ? '+' : ''}',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              square(
                tooltip: 'Previous page',
                onTap: page > 0 ? () => onPage(page - 1) : null,
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: page > 0 ? c.textSecondary : c.textMuted,
                ),
              ),
              for (var p = first; p < last; p++)
                square(
                  selected: p == page,
                  onTap: p == page ? null : () => onPage(p),
                  child: Text(
                    '${p + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p == page
                          ? adminOnActionColor(c)
                          : c.textSecondary,
                    ),
                  ),
                ),
              square(
                tooltip: 'Next page',
                onTap: page < pageCount - 1 ? () => onPage(page + 1) : null,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: page < pageCount - 1 ? c.textSecondary : c.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The background of a table row: a faint green when its box is ticked.
WidgetStateProperty<Color?> adminTableRowColor(AdminPalette c) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? adminActionColor(c).withValues(alpha: c.isDark ? 0.18 : 0.07)
          : Colors.transparent,
    );

/// One tab of an [AdminTabbedTable]: a view of the table and how many rows
/// it has. A null [count] shows no number: for a table whose rows are
/// loaded a page at a time, so their total is not known.
typedef AdminTableTab<T> = ({T value, String label, int? count, IconData icon});

/// What a tab's count badge says: the number, or "99+" from 100 up.
String adminTabCountLabel(int count) => count > 99 ? '99+' : '$count';

/// A table with its filter as folder tabs along the top — each a view of
/// the same table with its row count — in place of a dropdown beside it.
/// The tabs start at the table's left edge, each as wide as its content
/// and leaning over the next, and the open one joins the table's card.
class AdminTabbedTable<T> extends StatelessWidget {
  final List<AdminTableTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onSelected;

  /// The table's card (see [adminTableCard] with `tabbed: true`).
  final Widget child;

  /// True where the card fills a height it is given (a panel beside the
  /// map) instead of being as tall as its rows.
  final bool expand;

  /// Shown at the right end of the tabs' own row — the actions for the
  /// ticked rows. It sits over that row, so appearing and disappearing
  /// moves nothing on the page.
  final Widget? trailing;

  const AdminTabbedTable({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.child,
    this.expand = false,
    this.trailing,
  });

  static const double _tabHeight = 46;
  // How far a tab's slanted edge leans over the tab after it.
  static const double _slant = 20;
  static const double _inset = 16;
  static const double _iconSize = 17;
  static const double _gap = 8;

  static final TextStyle _labelStyle = TextStyle(
    fontFamily: kAdminFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _countStyle = TextStyle(
    fontFamily: kAdminFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _badgeWidth(int count) {
    final width = _textWidth(adminTabCountLabel(count), _countStyle) + 14;
    return width < 24 ? 24 : width;
  }

  // The room a tab's icon, label and count need, measured at the open
  // tab's bold weight so a tab does not change width when it is opened.
  double _naturalWidth(AdminTableTab<T> tab) =>
      _inset * 2 +
      _iconSize +
      _gap +
      _textWidth(tab.label, _labelStyle).ceilToDouble() +
      (tab.count == null ? 0 : _gap + _badgeWidth(tab.count!)) +
      4;

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return Stack(
      fit: expand ? StackFit.expand : StackFit.loose,
      children: [
        // The card starts where the tabs end, tucked one pixel under them
        // so the open tab covers the card's top border.
        Padding(
          padding: const EdgeInsets.only(top: _tabHeight - 1),
          child: child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _tabHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Each tab is as wide as its content. On a window too narrow
              // for them all, the row scrolls sideways.
              final natural = [for (final tab in tabs) _naturalWidth(tab)];
              final lefts = <double>[];
              var x = 0.0;
              for (final width in natural) {
                lefts.add(x);
                x += width;
              }

              Widget placed(int i) => Positioned(
                left: lefts[i],
                top: 0,
                bottom: 0,
                // Leans over the next tab by the width of its slant.
                width: natural[i] + _slant,
                child: _tab(c, tabs[i]),
              );

              final open = tabs.indexWhere((tab) => tab.value == selected);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  // Room for the last tab's slant too.
                  width: x + _slant + 4,
                  height: _tabHeight,
                  child: Stack(
                    children: [
                      // Right to left, so each tab lies over the one
                      // after it; the open tab over them all.
                      for (var i = tabs.length - 1; i >= 0; i--)
                        if (i != open) placed(i),
                      if (open >= 0) placed(open),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Last, so it is on top: the tabs' row spans the full width and
        // would otherwise take the clicks meant for these buttons.
        if (trailing != null)
          Positioned(
            top: 0,
            right: 0,
            height: _tabHeight - 4,
            child: Center(child: trailing),
          ),
      ],
    );
  }

  Widget _tab(AdminPalette c, AdminTableTab<T> tab) {
    final open = tab.value == selected;
    final action = adminActionColor(c);
    final onAction = adminOnActionColor(c);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(tab.value),
        child: CustomPaint(
          painter: _AdminTabPainter(
            // The open tab is the dark green of the table's header.
            fill: open ? action : c.surfaceAlt,
            border: open ? action : c.border,
            open: open,
            slant: _slant,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: _inset,
              right: _inset + _slant,
              top: open ? 0 : _AdminTabPainter.closedDrop,
            ),
            child: Row(
              children: [
                Icon(
                  tab.icon,
                  size: _iconSize,
                  color: open ? onAction : c.textMuted,
                ),
                const SizedBox(width: _gap),
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: _labelStyle.copyWith(
                      fontWeight: open ? FontWeight.w700 : FontWeight.w500,
                      color: open ? onAction : c.textSecondary,
                    ),
                  ),
                ),
                if (tab.count != null) ...[
                  const SizedBox(width: _gap),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: open
                          ? onAction.withValues(alpha: 0.22)
                          : action.withValues(alpha: c.isDark ? 0.28 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      adminTabCountLabel(tab.count!),
                      textAlign: TextAlign.center,
                      style: _countStyle.copyWith(
                        color: open ? onAction : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The outline of one folder tab: a rounded top-left corner, a flat top,
/// and a right edge that slants down over the next tab.
class _AdminTabPainter extends CustomPainter {
  final Color fill;
  final Color border;
  final bool open;
  final double slant;

  /// How much lower a closed tab's top sits than the open one's.
  static const double closedDrop = 5;

  const _AdminTabPainter({
    required this.fill,
    required this.border,
    required this.open,
    required this.slant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final top = open ? 0.5 : closedDrop;
    const r = 12.0;
    final outline = Path()
      ..moveTo(0.5, h)
      ..lineTo(0.5, top + r)
      ..quadraticBezierTo(0.5, top, r, top)
      ..lineTo(w - slant - 8, top)
      ..quadraticBezierTo(w - slant, top, w - slant + 3, top + 7)
      ..lineTo(w - 4, h - 7)
      ..quadraticBezierTo(w - 1, h, w + 3, h);
    canvas.drawPath(
      Path.from(outline)..close(),
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // The open tab runs into the card below: its foot hides the card's
    // top border.
    if (open) {
      canvas.drawRect(
        Rect.fromLTRB(1, h - 1.5, w - 2, h + 0.5),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_AdminTabPainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.open != open ||
      old.slant != slant;
}

/// The line under a table that says how many rows are ticked, with a way
/// to untick them all. Nothing when none are.
class AdminSelectionNote extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  const AdminSelectionNote({
    super.key,
    required this.count,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final c = AdminThemeScope.of(context).palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count selected',
          style: TextStyle(
            color: adminActionColor(c),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}

// None, so the header band runs to the card's edges.
const EdgeInsets kAdminTablePadding = EdgeInsets.zero;
const double kAdminTableColumnSpacing = 28;
const double kAdminTableMargin = 12;

/// Makes a table fill the width it is given: its columns spread out to
/// use the whole card on a wide window, and it scrolls sideways on one
/// too narrow for its columns.
///
/// It also keeps the table's header row in view: once the page has been
/// scrolled far enough that the header would leave the top of the screen,
/// the header stays there, over the rows, until the table itself ends.
class AdminTableFit extends StatefulWidget {
  final Widget table;
  const AdminTableFit({super.key, required this.table});

  @override
  State<AdminTableFit> createState() => _AdminTableFitState();
}

class _AdminTableFitState extends State<AdminTableFit> {
  final GlobalKey _tableKey = GlobalKey();

  // How far down the table its header is held, in pixels; 0 while the
  // header is where it normally is.
  final ValueNotifier<double> _pinned = ValueNotifier<double>(0);

  // The page's vertical scrolling, and where in the scrolled content the
  // table starts and how tall it is — measured after each layout.
  ScrollPosition? _scroll;
  double? _tableTop;
  double _tableHeight = 0;

  // A row's height, kept under the held header so it never slides past
  // the table's last row.
  static const double _lastRow = 48;

  double get _headerHeight {
    final table = widget.table;
    return (table is DataTable ? table.headingRowHeight : null) ??
        DataTableTheme.of(context).headingRowHeight ??
        56;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_onScroll);
      _scroll = scroll?..addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _pinned.dispose();
    super.dispose();
  }

  // After a layout: where the table now is in the scrolled content.
  void _measure() {
    if (!mounted) return;
    final scroll = _scroll;
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final table = _tableKey.currentContext?.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (scroll == null ||
        table is! RenderBox ||
        viewport is! RenderBox ||
        !table.attached ||
        !table.hasSize ||
        !viewport.attached) {
      return;
    }
    _tableTop =
        table.localToGlobal(Offset.zero, ancestor: viewport).dy + scroll.pixels;
    _tableHeight = table.size.height;
    _onScroll();
  }

  void _onScroll() {
    final scroll = _scroll;
    final top = _tableTop;
    if (scroll == null || top == null || !scroll.hasPixels) return;
    final room = _tableHeight - _headerHeight - _lastRow;
    final past = scroll.pixels - top;
    _pinned.value = past <= 0 || room <= 0 ? 0 : (past > room ? room : past);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final headerHeight = _headerHeight;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Stack(
            // The table takes the width it is given (the card's), as it
            // did before it shared a Stack with its held header.
            fit: StackFit.passthrough,
            children: [
              KeyedSubtree(key: _tableKey, child: widget.table),
              // The held header: the same table drawn again with all but
              // its header row cut off, so its columns line up exactly
              // and its select-all box still works. Only built while the
              // real header is off the top of the screen.
              ValueListenableBuilder<double>(
                valueListenable: _pinned,
                builder: (context, pinned, _) => pinned <= 0
                    ? const Positioned(
                        top: 0,
                        left: 0,
                        width: 0,
                        height: 0,
                        child: SizedBox.shrink(),
                      )
                    : Positioned(
                        top: pinned,
                        left: 0,
                        right: 0,
                        height: headerHeight,
                        child: ExcludeSemantics(
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: widget.table,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Month picker ----

/// A pill that shows a month and year ("October 2026") and opens a small
/// calendar of months under it: a year with arrows, and its twelve months.
/// For a period that is always a whole month — there are no days to pick.
class AdminMonthPill extends StatelessWidget {
  final int year;
  final int month;

  /// The years that can be chosen, both ends included.
  final int firstYear;
  final int lastYear;
  final void Function(int year, int month) onChanged;
  final double width;

  const AdminMonthPill({
    super.key,
    required this.year,
    required this.month,
    required this.firstYear,
    required this.lastYear,
    required this.onChanged,
    this.width = 190,
  });

  Future<void> _open(BuildContext context, AdminPalette c) async {
    final button = context.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return;
    final corner = button.localToGlobal(
      Offset(0, button.size.height + 6),
      ancestor: overlay,
    );
    final chosen = await showMenu<({int year, int month})>(
      context: context,
      position: RelativeRect.fromLTRB(
        corner.dx,
        corner.dy,
        overlay.size.width - corner.dx - button.size.width,
        0,
      ),
      color: c.surface,
      items: [
        // One item holding the whole calendar; its own cells are what is
        // clicked, not the item.
        PopupMenuItem<({int year, int month})>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AdminMonthCalendar(
            palette: c,
            year: year,
            month: month,
            firstYear: firstYear,
            lastYear: lastYear,
          ),
        ),
      ],
    );
    if (chosen == null) return;
    if (chosen.year != year || chosen.month != month) {
      onChanged(chosen.year, chosen.month);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AdminThemeScope.of(context).palette;
    return SizedBox(
      width: width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context, c),
          child: InputDecorator(
            decoration: adminPillDecoration(
              c,
              icon: Icons.calendar_month_outlined,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM y').format(DateTime(year, month)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kAdminFontFamily,
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: c.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminMonthCalendar extends StatefulWidget {
  final AdminPalette palette;
  final int year;
  final int month;
  final int firstYear;
  final int lastYear;

  const _AdminMonthCalendar({
    required this.palette,
    required this.year,
    required this.month,
    required this.firstYear,
    required this.lastYear,
  });

  @override
  State<_AdminMonthCalendar> createState() => _AdminMonthCalendarState();
}

class _AdminMonthCalendarState extends State<_AdminMonthCalendar> {
  // The year whose months are on show; the arrows change it.
  late int _year = widget.year.clamp(widget.firstYear, widget.lastYear);

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final action = adminActionColor(c);
    final today = DateTime.now();
    Widget arrow(IconData icon, String tooltip, bool enabled, int step) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, color: enabled ? c.textPrimary : c.textMuted),
          onPressed: enabled ? () => setState(() => _year += step) : null,
        );
    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                arrow(
                  Icons.chevron_left_rounded,
                  'Previous year',
                  _year > widget.firstYear,
                  -1,
                ),
                Expanded(
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kAdminFontFamily,
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                arrow(
                  Icons.chevron_right_rounded,
                  'Next year',
                  _year < widget.lastYear,
                  1,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var row = 0; row < 4; row++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    for (var column = 0; column < 3; column++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final month = row * 3 + column + 1;
                            final selected =
                                _year == widget.year && month == widget.month;
                            // A month that has not started has nothing in it.
                            final ahead =
                                _year > today.year ||
                                (_year == today.year && month > today.month);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Material(
                                color: selected ? action : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AdminRadii.pill,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AdminRadii.pill,
                                  ),
                                  onTap: ahead
                                      ? null
                                      : () => Navigator.of(
                                          context,
                                        ).pop((year: _year, month: month)),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 9,
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'MMM',
                                      ).format(DateTime(_year, month)),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: kAdminFontFamily,
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected
                                            ? adminOnActionColor(c)
                                            : ahead
                                            ? c.textMuted
                                            : c.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Profile avatar ----

/// "BE" for "Bernadeth Enriquez": the first letters of the first and last
/// words of a name. Empty when there is no name.
String adminInitials(String name) {
  final words = [
    for (final word in name.trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];
  if (words.isEmpty) return '';
  final first = words.first.substring(0, 1);
  final last = words.length > 1 ? words.last.substring(0, 1) : '';
  return (first + last).toUpperCase();
}

/// A user's profile picture as the portal shows it everywhere: their
/// CURRENT photo — the `photoUrl` on their own account record, the same
/// one the mobile app shows and updates — or, when they have not uploaded
/// one (a new farmer usually has not), a plain circle with their initials,
/// or a person icon when there is no name either.
///
/// Never a broken image: a photo that fails to load leaves the initials
/// showing. Works inside popups (it takes its colour from the theme).
class AdminAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double radius;

  const AdminAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final color = adminActionOf(context);
    final initials = adminInitials(name);
    final url = (photoUrl ?? '').trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color.alphaBlend(
        color.withValues(alpha: 0.14),
        Theme.of(context).colorScheme.surface,
      ),
      // The browser keeps the picture once fetched; it is asked for again
      // only when the farmer changes it (a new address).
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      onForegroundImageError: url.isEmpty ? null : (_, _) {},
      child: initials.isEmpty
          ? Icon(Icons.person_outline_rounded, color: color, size: radius)
          : Text(
              initials,
              style: TextStyle(
                fontFamily: kAdminFontFamily,
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: radius * (initials.length > 1 ? 0.68 : 0.8),
              ),
            ),
    );
  }
}
