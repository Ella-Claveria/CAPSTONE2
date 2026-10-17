import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audit_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/busy_indicator.dart';
import 'admin_dashboard_screen.dart' show AdminPalette;
import 'admin_filter_controls.dart';
import 'export_options_dialog.dart' show ReportFormat;

/// Which Audit Log entries go into the report.
enum AuditExportScope { allMatching, onScreen, selected }

/// Builds and hands over the report for the chosen entries; returns the
/// file's name. Supplied by the Audit Log page, which knows its entries.
typedef AuditExporter =
    Future<String> Function(
      AuditExportScope scope,
      AuditReportOptions options,
      void Function(String step) onProgress,
    );

const _prefsFormat = 'audit_export_format';
const _prefsParts = 'audit_export_parts';
const _prefsColumns = 'audit_export_columns';
const _prefsLandscape = 'audit_export_landscape';

/// The Audit Log's Export Report menu: the file format, which entries,
/// which parts of the report (activity summary, activity by admin, the
/// detailed log), which columns the log shows, the page orientation and
/// optional remarks. The last choices are remembered for next time.
class AuditExportDialog extends StatefulWidget {
  final AdminPalette palette;

  /// The page's filters, in words ("Login Activity · Oct 1 – 16, 2026").
  final String filtersLabel;
  final int onScreenCount;
  final int selectedCount;
  final AuditExporter exporter;

  const AuditExportDialog({
    super.key,
    required this.palette,
    required this.filtersLabel,
    required this.onScreenCount,
    required this.selectedCount,
    required this.exporter,
  });

  @override
  State<AuditExportDialog> createState() => _AuditExportDialogState();
}

class _AuditExportDialogState extends State<AuditExportDialog> {
  ReportFormat _format = ReportFormat.pdf;
  late AuditExportScope _scope = widget.selectedCount > 0
      ? AuditExportScope.selected
      : AuditExportScope.allMatching;
  final Set<AuditReportPart> _parts = {...AuditReportPart.values};
  final Set<AuditReportColumn> _columns = {...AuditReportColumn.values};
  bool _landscape = true;
  final TextEditingController _remarks = TextEditingController();

  bool _exporting = false;
  String _step = '';
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadLastChoices();
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final format = prefs.getString(_prefsFormat);
      final parts = prefs.getStringList(_prefsParts);
      final columns = prefs.getStringList(_prefsColumns);
      final landscape = prefs.getBool(_prefsLandscape);
      if (!mounted) return;
      setState(() {
        _format = const [
          ReportFormat.pdf,
          ReportFormat.excel,
          ReportFormat.csv,
        ].firstWhere((f) => f.name == format, orElse: () => ReportFormat.pdf);
        if (parts != null && parts.isNotEmpty) {
          _parts
            ..clear()
            ..addAll(
              AuditReportPart.values.where((p) => parts.contains(p.name)),
            );
        }
        if (columns != null && columns.isNotEmpty) {
          _columns
            ..clear()
            ..add(AuditReportColumn.dateTime)
            ..addAll(
              AuditReportColumn.values.where((c) => columns.contains(c.name)),
            );
        }
        if (landscape != null) _landscape = landscape;
      });
    } catch (_) {
      // First time here, or storage unavailable: the defaults stand.
    }
  }

  Future<void> _saveLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFormat, _format.name);
      await prefs.setStringList(_prefsParts, [for (final p in _parts) p.name]);
      await prefs.setStringList(_prefsColumns, [
        for (final c in _columns) c.name,
      ]);
      await prefs.setBool(_prefsLandscape, _landscape);
    } catch (_) {}
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _step = 'Gathering the entries…';
      _error = null;
      _success = null;
    });
    try {
      final filename = await widget.exporter(
        _scope,
        AuditReportOptions(
          format: _format,
          parts: {..._parts},
          // In the table's own order.
          columns: [
            for (final c in AuditReportColumn.values)
              if (_columns.contains(c)) c,
          ],
          landscape: _landscape,
          remarks: _remarks.text.trim(),
        ),
        (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      await _saveLastChoices();
      if (mounted) setState(() => _success = 'Exported $filename.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final primary = adminActionColor(c);
    final onPrimary = adminOnActionColor(c);
    final canExport = _parts.isNotEmpty && !_exporting;

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdminPopupRadius),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Audit Log',
                    style: TextStyle(
                      color: c.isDark ? c.textPrimary : AppTheme.dark,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Filters: ${widget.filtersLabel}',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(c, 'File Format'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (format, label) in const [
                          (ReportFormat.pdf, 'PDF'),
                          (ReportFormat.excel, 'Excel'),
                          (ReportFormat.csv, 'CSV'),
                        ])
                          _choice(
                            c,
                            label: label,
                            selected: _format == format,
                            onTap: () => setState(() => _format = format),
                          ),
                      ],
                    ),

                    _label(c, 'Entries to Include'),
                    _option(
                      c,
                      title: 'All entries matching the filters',
                      subtitle:
                          'Every matching entry, newest first (up to 2,000).',
                      selected: _scope == AuditExportScope.allMatching,
                      onTap: () =>
                          setState(() => _scope = AuditExportScope.allMatching),
                    ),
                    _option(
                      c,
                      title:
                          'Entries shown on screen (${widget.onScreenCount})',
                      subtitle:
                          'Only the entries loaded in the table right now.',
                      selected: _scope == AuditExportScope.onScreen,
                      onTap: () =>
                          setState(() => _scope = AuditExportScope.onScreen),
                    ),
                    _option(
                      c,
                      title: 'Selected entries (${widget.selectedCount})',
                      subtitle: widget.selectedCount == 0
                          ? 'Tick entries in the table to export only those.'
                          : 'Only the entries you ticked in the table.',
                      selected: _scope == AuditExportScope.selected,
                      onTap: widget.selectedCount == 0
                          ? null
                          : () => setState(
                              () => _scope = AuditExportScope.selected,
                            ),
                    ),

                    _label(
                      c,
                      'Report Content',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _link(
                            c,
                            'Select All',
                            c.green,
                            () => setState(
                              () => _parts.addAll(AuditReportPart.values),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _link(
                            c,
                            'Clear All',
                            c.textSecondary,
                            () => setState(_parts.clear),
                          ),
                        ],
                      ),
                    ),
                    for (final part in AuditReportPart.values)
                      _check(
                        c,
                        label: part.label,
                        subtitle: part.description,
                        value: _parts.contains(part),
                        onChanged: (on) => setState(
                          () => on ? _parts.add(part) : _parts.remove(part),
                        ),
                      ),

                    if (_parts.contains(AuditReportPart.log)) ...[
                      _label(c, 'Columns in the Detailed Log'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final column in AuditReportColumn.values)
                            _choice(
                              c,
                              label: column.label,
                              selected: _columns.contains(column),
                              check: true,
                              // Every entry keeps its date and time.
                              onTap: column == AuditReportColumn.dateTime
                                  ? null
                                  : () => setState(
                                      () => _columns.contains(column)
                                          ? _columns.remove(column)
                                          : _columns.add(column),
                                    ),
                            ),
                        ],
                      ),
                    ],

                    if (_format == ReportFormat.pdf) ...[
                      _label(c, 'PDF Options'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _choice(
                            c,
                            label: 'Landscape',
                            selected: _landscape,
                            radio: true,
                            onTap: () => setState(() => _landscape = true),
                          ),
                          _choice(
                            c,
                            label: 'Portrait',
                            selected: !_landscape,
                            radio: true,
                            onTap: () => setState(() => _landscape = false),
                          ),
                        ],
                      ),
                      _label(c, 'Remarks (optional)'),
                      AdminField(
                        controller: _remarks,
                        enabled: !_exporting,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 400,
                        decoration: adminMultilineDecoration(
                          context,
                          hintText:
                              'A note printed under the findings, e.g. the purpose of this report',
                        ),
                      ),
                    ],

                    if (_exporting) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.greenBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                // Drawn by the browser, so it keeps turning
                                // while the file is built.
                                BusySpinner(color: c.green),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _step,
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            BusyBar(color: c.green, trackColor: c.surface),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: c.red, fontSize: 12.5),
                      ),
                    ],
                    if (_success != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _success!,
                        style: TextStyle(color: c.green, fontSize: 12.5),
                      ),
                    ],
                    if (_parts.isEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Choose at least one part of the report.',
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: Text(_success == null ? 'Cancel' : 'Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canExport ? _export : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: onPrimary,
                      disabledBackgroundColor: _exporting
                          ? primary.withValues(alpha: 0.75)
                          : c.surfaceAlt,
                      disabledForegroundColor: _exporting
                          ? onPrimary
                          : c.textMuted,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(_exporting ? 'Exporting…' : 'Export'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A section's heading, with room above it.
  Widget _label(AdminPalette c, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _link(AdminPalette c, String text, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  // A pill: light green when chosen. With [radio] a radio dot, with
  // [check] a tick; a pill with no [onTap] is fixed.
  Widget _choice(
    AdminPalette c, {
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    bool radio = false,
    bool check = false,
  }) {
    final icon = radio
        ? (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded)
        : (check ? (selected ? Icons.check_rounded : Icons.add_rounded) : null);
    return Opacity(
      opacity: onTap == null && !selected ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.fromLTRB(icon != null ? 12 : 16, 9, 16, 9),
          decoration: BoxDecoration(
            color: selected ? c.greenBg : c.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? c.green : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? c.green : c.textMuted),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? c.green : c.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // One of the "Entries to Include" choices: a radio, a title and a line
  // under it. Without [onTap] it is shown but cannot be chosen.
  Widget _option(
    AdminPalette c, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? c.greenBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.green : c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? c.green : c.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _check(
    AdminPalette c, {
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (checked) => onChanged(checked ?? false),
                activeColor: c.green,
                checkColor: c.isDark ? Colors.black : Colors.white,
                side: BorderSide(color: c.textMuted, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5),
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
