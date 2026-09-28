import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/report_export_service.dart';
import 'admin_dashboard_screen.dart' show AdminPalette;

enum ReportFormat { pdf, excel, csv, png }

enum DateRangePreset { last7Days, last30Days, thisMonth, lastMonth, thisYear, custom }

/// One selectable Analytics Dashboard section, in the order the dashboard
/// itself renders them — [isChart] marks the 5 sections actually backed by
/// an fl_chart widget (the only ones PNG export can capture; everything
/// else is a data/list/table section).
enum DashboardSection {
  kpiSummary('KPI Summary', isChart: false),
  salesOverview('Sales Overview', isChart: true),
  salesByCategory('Sales by Category', isChart: true),
  priceTrend('Price Trend vs. Baseline', isChart: true),
  topSellingProducts('Top-Selling Products', isChart: false),
  demandByBarangay('Demand by Barangay', isChart: false),
  newRegistrations('New Registrations', isChart: true),
  verificationStatus('Verification Status', isChart: true),
  liveCommodityPrices('Live Commodity Prices', isChart: false),
  recentVerificationRequests('Recent Verification Requests', isChart: false);

  final String label;
  final bool isChart;
  const DashboardSection(this.label, {required this.isChart});
}

const _prefsKeyFormat = 'export_last_format';
const _prefsKeySections = 'export_last_sections';
const _prefsKeyPreset = 'export_last_preset';
const _prefsKeyOrientation = 'export_last_orientation';
const _prefsKeyIncludeTables = 'export_last_include_tables';
const _prefsKeyTitle = 'export_last_title';

class ExportOptionsDialog extends StatefulWidget {
  final AdminPalette palette;
  const ExportOptionsDialog({super.key, required this.palette});

  @override
  State<ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<ExportOptionsDialog> {
  ReportFormat _format = ReportFormat.pdf;
  final Set<DashboardSection> _sections = {...DashboardSection.values};
  final Set<String> _selectedCommodities = {};
  DateRangePreset _preset = DateRangePreset.last30Days;
  DateTimeRange? _customRange;

  final _titleController = TextEditingController(text: 'AgriTrade+ Analytics Report');
  bool _landscape = false;
  bool _includeDataTables = true;
  final _notesController = TextEditingController();

  bool _loadingPrefs = true;
  bool _exporting = false;
  String? _error;
  String? _successMessage;

  List<String> _availableCommodities = [];

  @override
  void initState() {
    super.initState();
    _loadCommodities();
    _loadLastChoices();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCommodities() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('market_prices').get();
      final names = snap.docs.map((d) => (d.data()['name'] ?? d.id).toString()).toList()..sort();
      if (mounted) {
        setState(() {
          _availableCommodities = names;
          _selectedCommodities.addAll(names);
        });
      }
    } catch (_) {
      // Commodity multi-select just stays empty — Price Trend section
      // (if selected) will report no data for this period, rather than
      // blocking the whole dialog on this best-effort lookup.
    }
  }

  Future<void> _loadLastChoices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatName = prefs.getString(_prefsKeyFormat);
      final sectionNames = prefs.getStringList(_prefsKeySections);
      final presetName = prefs.getString(_prefsKeyPreset);
      final orientationLandscape = prefs.getBool(_prefsKeyOrientation);
      final includeTables = prefs.getBool(_prefsKeyIncludeTables);
      final title = prefs.getString(_prefsKeyTitle);

      if (!mounted) return;
      setState(() {
        if (formatName != null) {
          _format = ReportFormat.values.firstWhere((f) => f.name == formatName, orElse: () => ReportFormat.pdf);
        }
        if (sectionNames != null && sectionNames.isNotEmpty) {
          _sections
            ..clear()
            ..addAll(DashboardSection.values.where((s) => sectionNames.contains(s.name)));
        }
        if (presetName != null) {
          _preset = DateRangePreset.values
              .firstWhere((p) => p.name == presetName, orElse: () => DateRangePreset.last30Days);
          if (_preset == DateRangePreset.custom) _preset = DateRangePreset.last30Days;
        }
        if (orientationLandscape != null) _landscape = orientationLandscape;
        if (includeTables != null) _includeDataTables = includeTables;
        if (title != null && title.trim().isNotEmpty) _titleController.text = title;
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
      await prefs.setStringList(_prefsKeySections, _sections.map((s) => s.name).toList());
      await prefs.setString(_prefsKeyPreset, _preset.name);
      await prefs.setBool(_prefsKeyOrientation, _landscape);
      await prefs.setBool(_prefsKeyIncludeTables, _includeDataTables);
      await prefs.setString(_prefsKeyTitle, _titleController.text.trim());
    } catch (_) {
      // Not remembering the choice next time is a fine failure mode —
      // never blocks the export itself.
    }
  }

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case DateRangePreset.last7Days:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case DateRangePreset.last30Days:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case DateRangePreset.thisMonth:
        return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
      case DateRangePreset.lastMonth:
        final firstOfThisMonth = DateTime(today.year, today.month, 1);
        final lastMonthEnd = firstOfThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1), end: lastMonthEnd);
      case DateRangePreset.thisYear:
        return DateTimeRange(start: DateTime(today.year, 1, 1), end: today);
      case DateRangePreset.custom:
        return _customRange ?? DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ?? _resolveRange(),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _preset = DateRangePreset.custom;
    });
  }

  bool _isSectionEnabled(DashboardSection s) {
    if (_format == ReportFormat.png) return s.isChart;
    return true;
  }

  void _onFormatChanged(ReportFormat format) {
    setState(() {
      _format = format;
      if (format == ReportFormat.png) {
        // PNG only ever makes sense for chart-backed sections — drop
        // anything else that was selected instead of silently ignoring it.
        _sections.removeWhere((s) => !s.isChart);
      }
    });
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final range = _format == ReportFormat.png ? null : _resolveRange();
      final result = await ReportExportService.export(
        format: _format,
        sections: _sections,
        selectedCommodities: _selectedCommodities,
        range: range,
        reportTitle: _titleController.text.trim().isEmpty
            ? 'AgriTrade+ Analytics Report'
            : _titleController.text.trim(),
        landscape: _landscape,
        includeDataTables: _includeDataTables,
        notes: _notesController.text,
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
    final canExport = _sections.isNotEmpty && !_exporting;
    final showCommodityPicker = _sections.contains(DashboardSection.priceTrend) && _availableCommodities.isNotEmpty;
    final showPngRangeNote = _format == ReportFormat.png || _sections.any((s) => s.isChart);

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: _loadingPrefs
            ? Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator(color: c.green)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Text('Export Report',
                        style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel(c, 'File format'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ReportFormat.values.map((f) {
                              final selected = _format == f;
                              return ChoiceChip(
                                label: Text(_formatLabel(f)),
                                selected: selected,
                                onSelected: (_) => _onFormatChanged(f),
                                selectedColor: c.greenBg,
                                backgroundColor: c.surfaceAlt,
                                labelStyle: TextStyle(color: selected ? c.green : c.textSecondary, fontSize: 13),
                                side: BorderSide(color: selected ? c.green : c.border),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _sectionLabel(c, 'Sections to include'),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _sections
                                        ..clear()
                                        ..addAll(DashboardSection.values.where(_isSectionEnabled));
                                    }),
                                    child: Text('Select all', style: TextStyle(color: c.green, fontSize: 12.5)),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() => _sections.clear()),
                                    child:
                                        Text('Clear all', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_format == ReportFormat.png)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'PNG only supports chart-based sections.',
                                style: TextStyle(color: c.textMuted, fontSize: 11.5),
                              ),
                            ),
                          ...DashboardSection.values.map((s) {
                            final enabled = _isSectionEnabled(s);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _sections.contains(s),
                              enabled: enabled,
                              onChanged: !enabled
                                  ? null
                                  : (v) => setState(() {
                                        if (v == true) {
                                          _sections.add(s);
                                        } else {
                                          _sections.remove(s);
                                        }
                                      }),
                              activeColor: c.green,
                              title: Text(
                                s.label,
                                style: TextStyle(
                                  color: enabled ? c.textPrimary : c.textMuted,
                                  fontSize: 13.5,
                                ),
                              ),
                            );
                          }),

                          if (showCommodityPicker) ...[
                            const SizedBox(height: 4),
                            _sectionLabel(c, 'Commodities for Price Trend'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _availableCommodities.map((name) {
                                final selected = _selectedCommodities.contains(name);
                                return FilterChip(
                                  label: Text(name, style: const TextStyle(fontSize: 12.5)),
                                  selected: selected,
                                  onSelected: (v) => setState(() {
                                    if (v) {
                                      _selectedCommodities.add(name);
                                    } else {
                                      _selectedCommodities.remove(name);
                                    }
                                  }),
                                  selectedColor: c.greenBg,
                                  backgroundColor: c.surfaceAlt,
                                  labelStyle: TextStyle(color: selected ? c.green : c.textSecondary),
                                  side: BorderSide(color: selected ? c.green : c.border),
                                );
                              }).toList(),
                            ),
                          ],

                          const SizedBox(height: 20),
                          _sectionLabel(c, 'Date range'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in DateRangePreset.values.where((p) => p != DateRangePreset.custom))
                                _presetChip(c, p),
                              ActionChip(
                                label: Text(
                                  _preset == DateRangePreset.custom && _customRange != null
                                      ? '${DateFormat('MMM d').format(_customRange!.start)} – ${DateFormat('MMM d, y').format(_customRange!.end)}'
                                      : 'Custom…',
                                ),
                                onPressed: _pickCustomRange,
                                backgroundColor:
                                    _preset == DateRangePreset.custom ? c.greenBg : c.surfaceAlt,
                                labelStyle: TextStyle(
                                  color: _preset == DateRangePreset.custom ? c.green : c.textSecondary,
                                  fontSize: 12.5,
                                ),
                                side: BorderSide(
                                    color: _preset == DateRangePreset.custom ? c.green : c.border),
                              ),
                            ],
                          ),
                          if (_format == ReportFormat.png)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'PNG captures each chart exactly as currently shown on the dashboard — the date range above doesn\'t apply to it.',
                                style: TextStyle(color: c.textMuted, fontSize: 11.5),
                              ),
                            )
                          else if (showPngRangeNote)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Note: chart images for chart-based sections reflect the dashboard\'s current live view; the data tables reflect the date range above.',
                                style: TextStyle(color: c.textMuted, fontSize: 11.5),
                              ),
                            ),

                          if (_format == ReportFormat.pdf) ...[
                            const SizedBox(height: 20),
                            _sectionLabel(c, 'PDF options'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _titleController,
                              style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                              decoration: _fieldDecoration(c, 'Report title'),
                            ),
                            const SizedBox(height: 12),
                            RadioGroup<bool>(
                              groupValue: _landscape,
                              onChanged: (v) => setState(() => _landscape = v ?? false),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: RadioListTile<bool>(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: false,
                                      activeColor: c.green,
                                      title:
                                          Text('Portrait', style: TextStyle(color: c.textPrimary, fontSize: 13)),
                                    ),
                                  ),
                                  Expanded(
                                    child: RadioListTile<bool>(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      value: true,
                                      activeColor: c.green,
                                      title: Text('Landscape',
                                          style: TextStyle(color: c.textPrimary, fontSize: 13)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: _includeDataTables,
                              onChanged: (v) => setState(() => _includeDataTables = v),
                              activeThumbColor: c.green,
                              title: Text('Include data tables under each chart',
                                  style: TextStyle(color: c.textPrimary, fontSize: 13)),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notesController,
                              style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                              maxLines: 3,
                              decoration: _fieldDecoration(c, 'Notes / remarks (optional, shown on page 1)'),
                            ),
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(_error!, style: TextStyle(color: c.red, fontSize: 12.5)),
                          ],
                          if (_successMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(_successMessage!, style: TextStyle(color: c.green, fontSize: 12.5)),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
                          child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: canExport ? _export : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.green,
                            foregroundColor: c.isDark ? Colors.black : Colors.white,
                            disabledBackgroundColor: c.surfaceAlt,
                          ),
                          child: _exporting
                              ? SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: c.isDark ? Colors.black : Colors.white),
                                )
                              : const Text('Export'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _presetChip(AdminPalette c, DateRangePreset p) {
    final selected = _preset == p;
    return ChoiceChip(
      label: Text(_presetLabel(p), style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => setState(() => _preset = p),
      selectedColor: c.greenBg,
      backgroundColor: c.surfaceAlt,
      labelStyle: TextStyle(color: selected ? c.green : c.textSecondary),
      side: BorderSide(color: selected ? c.green : c.border),
    );
  }

  Widget _sectionLabel(AdminPalette c, String text) =>
      Text(text, style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700));

  InputDecoration _fieldDecoration(AdminPalette c, String label) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
      filled: true,
      fillColor: c.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  String _formatLabel(ReportFormat f) => switch (f) {
        ReportFormat.pdf => 'PDF',
        ReportFormat.excel => 'Excel (.xlsx)',
        ReportFormat.csv => 'CSV',
        ReportFormat.png => 'PNG',
      };

  String _presetLabel(DateRangePreset p) => switch (p) {
        DateRangePreset.last7Days => 'Last 7 days',
        DateRangePreset.last30Days => 'Last 30 days',
        DateRangePreset.thisMonth => 'This month',
        DateRangePreset.lastMonth => 'Last month',
        DateRangePreset.thisYear => 'This year',
        DateRangePreset.custom => 'Custom',
      };
}
