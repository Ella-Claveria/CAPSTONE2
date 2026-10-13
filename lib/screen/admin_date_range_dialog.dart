import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'admin_dashboard_screen.dart';
import 'admin_filter_controls.dart';

/// The portal's date range picker: a popup card in the portal's own look —
/// the two dates on top, shortcuts for the usual ranges, one month at a
/// time with arrows, the chosen days joined by a pale green band.
///
/// [palette] is for a caller that is itself a popup (which has no
/// AdminThemeScope above it).
Future<DateTimeRange?> showAdminDateRangePicker(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  AdminPalette? palette,
}) {
  final c =
      palette ??
      context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
      (Theme.of(context).brightness == Brightness.dark
          ? AdminPalette.dark
          : AdminPalette.light);
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => AdminDateRangeDialog(
      palette: c,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
    ),
  );
}

/// The same calendar for one date (a price's date, an announcement's
/// day): a click on a day chooses it.
Future<DateTime?> showAdminDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Select date',
  AdminPalette? palette,
}) async {
  final c =
      palette ??
      context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
      (Theme.of(context).brightness == Brightness.dark
          ? AdminPalette.dark
          : AdminPalette.light);
  final picked = await showDialog<DateTimeRange>(
    context: context,
    builder: (_) => AdminDateRangeDialog(
      palette: c,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: initialDate, end: initialDate),
      single: true,
      title: title,
    ),
  );
  return picked?.start;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class AdminDateRangeDialog extends StatefulWidget {
  final AdminPalette palette;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  /// One date instead of a range.
  final bool single;
  final String title;

  const AdminDateRangeDialog({
    super.key,
    required this.palette,
    required this.firstDate,
    required this.lastDate,
    this.initialDateRange,
    this.single = false,
    this.title = 'Select date range',
  });

  @override
  State<AdminDateRangeDialog> createState() => _AdminDateRangeDialogState();
}

class _AdminDateRangeDialogState extends State<AdminDateRangeDialog> {
  late final DateTime _first = _day(widget.firstDate);
  late final DateTime _last = _day(widget.lastDate);

  DateTime? _start;
  DateTime? _end;
  // The day under the pointer while the end date is still to be chosen.
  DateTime? _hover;
  // The first day of the month on show.
  late DateTime _month;

  static final _dateLabel = DateFormat('MMM d, yyyy');
  static final _monthLabel = DateFormat('MMMM yyyy');

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    if (initial != null) {
      _start = _clamp(_day(initial.start));
      _end = _clamp(_day(initial.end));
    }
    // The chosen date's month; with none chosen, this month (or the
    // nearest one that can be chosen from).
    final shown = _end ?? _clamp(_day(DateTime.now()));
    _month = DateTime(shown.year, shown.month);
  }

  DateTime _clamp(DateTime d) =>
      d.isBefore(_first) ? _first : (d.isAfter(_last) ? _last : d);

  bool _selectable(DateTime d) => !d.isBefore(_first) && !d.isAfter(_last);

  void _pick(DateTime day) => setState(() {
    final start = _start;
    if (widget.single) {
      _start = day;
      _end = day;
    } else if (start == null || _end != null || day.isBefore(start)) {
      // A first click, or starting over.
      _start = day;
      _end = null;
    } else {
      _end = day;
    }
    _hover = null;
  });

  void _preset(DateTime start, DateTime end) => setState(() {
    _start = _clamp(start);
    _end = _clamp(end);
    _hover = null;
    _month = DateTime(_end!.year, _end!.month);
  });

  bool get _canGoBack => _month.isAfter(DateTime(_first.year, _first.month));
  bool get _canGoForward => _month.isBefore(DateTime(_last.year, _last.month));

  void _turn(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  TextStyle _text(Color color, double size, [FontWeight? weight]) => TextStyle(
    fontFamily: kAdminFontFamily,
    color: color,
    fontSize: size,
    fontWeight: weight,
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final action = adminActionColor(c);
    final start = _start;

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdminPopupRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: _text(c.textPrimary, 16, FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: c.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.single)
                _dateBox(c, 'Date', start)
              else
                Row(
                  children: [
                    Expanded(child: _dateBox(c, 'Start date', start)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: c.textMuted,
                      ),
                    ),
                    Expanded(child: _dateBox(c, 'End date', _end)),
                  ],
                ),
              const SizedBox(height: 12),
              if (widget.single) ...[
                if (_selectable(_day(DateTime.now())))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _presetChip(c, 'Today', () {
                      final today = _day(DateTime.now());
                      _preset(today, today);
                    }),
                  ),
              ] else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _presetChip(c, 'Today', () => _preset(_last, _last)),
                    _presetChip(
                      c,
                      'Last 7 days',
                      () => _preset(
                        _last.subtract(const Duration(days: 6)),
                        _last,
                      ),
                    ),
                    _presetChip(
                      c,
                      'Last 30 days',
                      () => _preset(
                        _last.subtract(const Duration(days: 29)),
                        _last,
                      ),
                    ),
                    _presetChip(
                      c,
                      'This month',
                      () => _preset(DateTime(_last.year, _last.month), _last),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  _arrow(
                    c,
                    Icons.chevron_left_rounded,
                    'Previous month',
                    _canGoBack ? () => _turn(-1) : null,
                  ),
                  Expanded(
                    child: Text(
                      _monthLabel.format(_month),
                      textAlign: TextAlign.center,
                      style: _text(c.textPrimary, 14, FontWeight.w700),
                    ),
                  ),
                  _arrow(
                    c,
                    Icons.chevron_right_rounded,
                    'Next month',
                    _canGoForward ? () => _turn(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: _text(c.textMuted, 11.5, FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              ..._weeks(c, action),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (start != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _start = null;
                        _end = null;
                        _hover = null;
                      }),
                      child: Text(
                        'Clear',
                        style: _text(c.textSecondary, 13, FontWeight.w600),
                      ),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: _text(c.textPrimary, 13, FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    // One day chosen is a range of that day.
                    onPressed: start == null
                        ? null
                        : () => Navigator.of(context).pop(
                            DateTimeRange(start: start, end: _end ?? start),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: action,
                      foregroundColor: c.isDark ? c.bg : Colors.white,
                      disabledBackgroundColor: c.border,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        fontFamily: kAdminFontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateBox(AdminPalette c, String label, DateTime? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _text(c.textMuted, 10.5, FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            value == null ? '—' : _dateLabel.format(value),
            style: _text(
              value == null ? c.textMuted : c.textPrimary,
              13,
              FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(AdminPalette c, String label, VoidCallback onTap) {
    return Material(
      color: c.greenBg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: _text(adminActionColor(c), 11.5, FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _arrow(
    AdminPalette c,
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
  ) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 22,
        color: onTap == null ? c.border : c.textPrimary,
      ),
    );
  }

  // The month as rows of seven days, Sunday first.
  List<Widget> _weeks(AdminPalette c, Color action) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return [
      for (var i = 0; i < cells.length; i += 7)
        Row(
          children: [
            for (final day in cells.sublist(i, i + 7))
              Expanded(
                child: day == null
                    ? const SizedBox(height: 40)
                    : _dayCell(c, action, day),
              ),
          ],
        ),
    ];
  }

  Widget _dayCell(AdminPalette c, Color action, DateTime day) {
    final start = _start;
    // While the end is still to be chosen, the day under the pointer
    // stands in for it.
    final hover = _hover;
    final end =
        _end ??
        (start != null && hover != null && hover.isAfter(start) ? hover : null);
    final isStart = start != null && day == start;
    final isEnd = end != null && day == end;
    final inRange =
        start != null && end != null && day.isAfter(start) && day.isBefore(end);
    final hasRange = start != null && end != null && end != start;
    final enabled = _selectable(day);
    final isToday = day == _day(DateTime.now());
    final chosen = isStart || (isEnd && _end != null);
    final band = c.greenBg;

    final cell = SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The band joining the two dates.
          if (inRange)
            Positioned.fill(top: 4, bottom: 4, child: ColoredBox(color: band)),
          if (hasRange && (isStart || isEnd))
            Positioned.fill(
              top: 4,
              bottom: 4,
              child: FractionallySizedBox(
                alignment: isStart
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                widthFactor: 0.5,
                child: ColoredBox(color: band),
              ),
            ),
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chosen ? action : null,
              border: !chosen && (isToday || isEnd)
                  ? Border.all(color: action, width: 1.2)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: _text(
                chosen
                    ? (c.isDark ? c.bg : Colors.white)
                    : enabled
                    ? c.textPrimary
                    : c.textMuted.withValues(alpha: 0.45),
                12.5,
                chosen || isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (!enabled) return cell;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (_start != null && _end == null) setState(() => _hover = day);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(day),
        child: cell,
      ),
    );
  }
}
