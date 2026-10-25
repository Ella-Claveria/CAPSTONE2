import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/report_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/busy_indicator.dart';
import 'admin_dashboard_screen.dart' show AdminPalette;
import 'admin_filter_controls.dart';

enum ReportFormat { pdf, excel, csv, png }

enum DateRangePreset {
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

/// One selectable Analytics Dashboard section, in the order the dashboard
/// itself renders them — [isChart] marks the 3 sections actually backed by
/// an fl_chart widget (the only ones PNG export can capture; everything
/// else is a data/list/table section).
enum DashboardSection {
  kpiSummary('KPI Summary', isChart: false),
  salesOverview('Sales Overview', isChart: true),
  salesByCategory('Sales by Category', isChart: true),
  priceTrend('Price Trend vs. Baseline', isChart: true),
  topSellingProducts('Top-Selling Products', isChart: false),
  demandByBarangay('Demand by Barangay', isChart: false),
  newRegistrations('New Registrations', isChart: false),
  verificationStatus('Verification Status', isChart: false),
  liveCommodityPrices('Live Commodity Prices', isChart: false),
  recentVerificationRequests('Recent Verification Requests', isChart: false);

  final String label;
  final bool isChart;
  const DashboardSection(this.label, {required this.isChart});
}

/// What the Export Report dialog offers, in place of one checkbox per
/// dashboard section: four groups, each standing for the sections listed.
enum ReportGroup {
  overview('Overview Summary', {DashboardSection.kpiSummary}),
  sales('Sales Analytics', {
    DashboardSection.salesOverview,
    DashboardSection.salesByCategory,
    DashboardSection.topSellingProducts,
  }),
  demandAndMarket('Demand & Market Analytics', {
    DashboardSection.priceTrend,
    DashboardSection.demandByBarangay,
    DashboardSection.liveCommodityPrices,
  }),
  verification('Verification & User Summary', {
    DashboardSection.newRegistrations,
    DashboardSection.verificationStatus,
    DashboardSection.recentVerificationRequests,
  });

  final String label;
  final Set<DashboardSection> sections;
  const ReportGroup(this.label, this.sections);
}

/// The file formats and date ranges the dialog offers. The export service
/// still understands the others (CSV, PNG, last 7 days); they are simply
/// no longer offered.
const List<ReportFormat> kOfferedReportFormats = [
  ReportFormat.pdf,
  ReportFormat.excel,
];
const List<DateRangePreset> kOfferedDatePresets = [
  DateRangePreset.last30Days,
  DateRangePreset.thisMonth,
  DateRangePreset.lastMonth,
  DateRangePreset.thisYear,
];

const String _reportTitle = 'AgriTrade+ Analytics Report';

const _prefsKeyFormat = 'export_last_format';
const _prefsKeyGroups = 'export_last_groups';
const _prefsKeyPreset = 'export_last_preset';
const _prefsKeyOrientation = 'export_last_orientation';
const _prefsKeyIncludeTables = 'export_last_include_tables';

class ExportOptionsDialog extends StatefulWidget {
  final AdminPalette palette;
  const ExportOptionsDialog({super.key, required this.palette});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ReportFormat _format = ReportFormat.pdf;
  final Set<ReportGroup> _groups = {...ReportGroup.values};
  // Null = every commodity.
  String? _commodity;
  DateRangePreset _preset = DateRangePreset.last30Days;
  DateTimeRange? _customRange;
  bool _landscape = false;
  bool _includeDataTables = true;

  bool _loadingPrefs = true;
  bool _exporting = false;
  // What the export is doing right now, shown while it runs.
  String _step = '';
  String? _error;
  String? _successMessage;

  List<String> _availableCommodities = [];

  @override
  void initState() {
    super.initState();
    _loadCommodities();
    _loadLastChoices();
  }

  Future<void> _loadCommodities() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('market_prices')
          .get();
      final names =
          snap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()
            ..sort();
      if (mounted) setState(() => _availableCommodities = names);
    } catch (_) {
      // The dropdown just stays on "All Commodities" — never blocks the
      // dialog on this best-effort lookup.
    }
  }

  Future<void> _loadLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatName = prefs.getString(_prefsKeyFormat);
      final groupNames = prefs.getStringList(_prefsKeyGroups);
      final presetName = prefs.getString(_prefsKeyPreset);
      final orientationLandscape = prefs.getBool(_prefsKeyOrientation);
      final includeTables = prefs.getBool(_prefsKeyIncludeTables);

      if (!mounted) return;
      setState(() {
        // A format or range remembered from before that is no longer
        // offered falls back to the default.
        _format = kOfferedReportFormats.firstWhere(
          (f) => f.name == formatName,
          orElse: () => ReportFormat.pdf,
        );
        if (groupNames != null && groupNames.isNotEmpty) {
          _groups
            ..clear()
            ..addAll(
              ReportGroup.values.where((g) => groupNames.contains(g.name)),
            );
        }
        _preset = kOfferedDatePresets.firstWhere(
          (p) => p.name == presetName,
          orElse: () => DateRangePreset.last30Days,
        );
        if (orientationLandscape != null) _landscape = orientationLandscape;
        if (includeTables != null) _includeDataTables = includeTables;
        _loadingPrefs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _saveLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyFormat, _format.name);
      await prefs.setStringList(
        _prefsKeyGroups,
        _groups.map((g) => g.name).toList(),
      );
      await prefs.setString(_prefsKeyPreset, _preset.name);
      await prefs.setBool(_prefsKeyOrientation, _landscape);
      await prefs.setBool(_prefsKeyIncludeTables, _includeDataTables);
    } catch (_) {
      // Not remembering the choice next time is a fine failure mode —
      // never blocks the export itself.
    }
  }

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last30 = DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
    switch (_preset) {
      case DateRangePreset.last7Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case DateRangePreset.last30Days:
        return last30;
      case DateRangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
      case DateRangePreset.lastMonth:
        final firstOfThisMonth = DateTime(today.year, today.month, 1);
        final lastMonthEnd = firstOfThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
          end: lastMonthEnd,
        );
      case DateRangePreset.thisYear:
        return DateTimeRange(start: DateTime(today.year, 1, 1), end: today);
      case DateRangePreset.custom:
        return _customRange ?? last30;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showAdminDateRangePicker(
      context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ?? _resolveRange(),
      palette: widget.palette,
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _preset = DateRangePreset.custom;
    });
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _step = 'Starting…';
      _error = null;
      _successMessage = null;
    });

    try {
      final result = await ReportExportService.export(
        format: _format,
        sections: {for (final group in _groups) ...group.sections},
        selectedCommodities: _commodity == null
            ? _availableCommodities.toSet()
            : {_commodity!},
        range: _resolveRange(),
        reportTitle: _reportTitle,
        landscape: _landscape,
        includeDataTables: _includeDataTables,
        notes: '',
        onProgress: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      await _saveLastChoices();
      if (!mounted) return;
      if (result.missingDataSections.isNotEmpty) {
        setState(() {
          _successMessage =
              'Exported ${result.filename}. No data for this period: ${result.missingDataSections.join(', ')}.';
        });
      } else {
        setState(() => _successMessage = 'Exported ${result.filename}.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final canExport = _groups.isNotEmpty && !_exporting;
    // The app's dark green on a light page; the portal's green on a dark one.
    final primary = adminActionColor(c);
    final onPrimary = adminOnActionColor(c);

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAdminPopupRadius),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _loadingPrefs
            ? Padding(
                padding: const EdgeInsets.all(48),
                child: const Center(child: AdminLoadingBar()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                    child: Text(
                      'Export Report',
                      style: TextStyle(
                        color: c.isDark ? c.textPrimary : AppTheme.dark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Scrolls only when the window is too short for it all;
                  // the buttons below stay in view either way.
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
                              for (final format in kOfferedReportFormats)
                                _choice(
                                  c,
                                  label: format == ReportFormat.pdf
                                      ? 'PDF'
                                      : 'Excel',
                                  selected: _format == format,
                                  onTap: () => setState(() => _format = format),
                                ),
                            ],
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
                                    () => _groups.addAll(ReportGroup.values),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                _link(
                                  c,
                                  'Clear All',
                                  c.textSecondary,
                                  () => setState(_groups.clear),
                                ),
                              ],
                            ),
                          ),
                          for (final group in ReportGroup.values)
                            _check(
                              c,
                              label: group.label,
                              value: _groups.contains(group),
                              onChanged: (checked) => setState(() {
                                if (checked) {
                                  _groups.add(group);
                                } else {
                                  _groups.remove(group);
                                }
                              }),
                            ),

                          _label(c, 'Commodity'),
                          DropdownButtonFormField<String?>(
                            key: ValueKey(
                              '$_commodity-${_availableCommodities.length}',
                            ),
                            initialValue:
                                _availableCommodities.contains(_commodity)
                                ? _commodity
                                : null,
                            isExpanded: true,
                            isDense: true,
                            menuMaxHeight: 320,
                            style: TextStyle(
                              fontFamily: kAdminFontFamily,
                              color: c.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            icon: Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                              color: c.textSecondary,
                            ),
                            dropdownColor: c.surface,
                            borderRadius: BorderRadius.circular(
                              kAdminPopupRadius,
                            ),
                            decoration: adminPillDecoration(c),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('All Commodities'),
                              ),
                              for (final name in _availableCommodities)
                                DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _commodity = value),
                          ),

                          _label(c, 'Date Range'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in kOfferedDatePresets)
                                _choice(
                                  c,
                                  label: _presetLabel(preset),
                                  selected: _preset == preset,
                                  onTap: () => setState(() => _preset = preset),
                                ),
                              _choice(
                                c,
                                label:
                                    _preset == DateRangePreset.custom &&
                                        _customRange != null
                                    ? '${DateFormat('MMM d').format(_customRange!.start)} – ${DateFormat('MMM d, y').format(_customRange!.end)}'
                                    : 'Custom',
                                selected: _preset == DateRangePreset.custom,
                                onTap: _pickCustomRange,
                              ),
                            ],
                          ),

                          if (_format == ReportFormat.pdf) ...[
                            _label(c, 'PDF Options'),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _choice(
                                  c,
                                  label: 'Portrait',
                                  selected: !_landscape,
                                  radio: true,
                                  onTap: () =>
                                      setState(() => _landscape = false),
                                ),
                                _choice(
                                  c,
                                  label: 'Landscape',
                                  selected: _landscape,
                                  radio: true,
                                  onTap: () =>
                                      setState(() => _landscape = true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _check(
                              c,
                              label: 'Include data tables',
                              value: _includeDataTables,
                              onChanged: (checked) =>
                                  setState(() => _includeDataTables = checked),
                            ),
                          ],

                          if (_exporting) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: c.greenBg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      // Drawn by the browser, so it keeps
                                      // turning while the file is built.
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
                                  BusyBar(
                                    color: c.green,
                                    trackColor: c.surface,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Please keep this window open. A report '
                                    'with charts can take a little while.',
                                    style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
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
                          if (_successMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _successMessage!,
                              style: TextStyle(color: c.green, fontSize: 12.5),
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
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: canExport ? _export : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: onPrimary,
                            // Stays green while exporting, so its
                            // "Exporting…" can be read.
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
                              fontFamily: 'Montserrat',
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
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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

  // A pill to choose one of a few options: light green when chosen. With
  // [radio] it carries a radio dot, for an either/or pair.
  Widget _choice(
    AdminPalette c, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool radio = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.fromLTRB(radio ? 12 : 16, 9, 16, 9),
        decoration: BoxDecoration(
          color: selected ? c.greenBg : c.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.green : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (radio) ...[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: selected ? c.green : c.textMuted,
              ),
              const SizedBox(width: 8),
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
    );
  }

  Widget _check(
    AdminPalette c, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
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
              child: Text(
                label,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _presetLabel(DateRangePreset p) => switch (p) {
    DateRangePreset.last7Days => 'Last 7 Days',
    DateRangePreset.last30Days => 'Last 30 Days',
    DateRangePreset.thisMonth => 'This Month',
    DateRangePreset.lastMonth => 'Last Month',
    DateRangePreset.thisYear => 'This Year',
    DateRangePreset.custom => 'Custom',
  };
}
