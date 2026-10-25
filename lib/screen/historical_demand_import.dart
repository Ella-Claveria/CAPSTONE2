import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/commodity_master_list.dart';
import '../services/historical_demand_service.dart';
import 'admin_filter_controls.dart';
import 'admin_dashboard_screen.dart' show AdminPalette, AdminThemeScope;

/// Admin → Market Forecasts → Import Historical Data: pick an Excel or CSV
/// file, see every row checked before anything is saved, then confirm.
/// Valid rows go to `historical_demand` only — no orders are created.
///
/// Returns how many records were saved (0 if the import was cancelled).
Future<int> showHistoricalDemandImport(BuildContext context) async {
  final palette = AdminThemeScope.of(context).palette;
  final messenger = ScaffoldMessenger.of(context);

  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'xlsx'],
  );
  if (files.isEmpty) return 0;
  final file = files.first;

  final List<List<String>> table;
  try {
    final bytes = await file.readAsBytes();
    table = (file.extension ?? '').toLowerCase() == 'xlsx'
        ? readXlsxTable(bytes)
        : readCsvTable(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not read that file. Use an .xlsx or .csv file with a '
          'header row.',
        ),
      ),
    );
    return 0;
  }
  if (!context.mounted) return 0;

  final result = HistoricalDemandService.validate(
    table,
    supported: CommodityRegistry.instance.all,
  );
  final saved = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _HistoricalDemandPreviewDialog(
      palette: palette,
      fileName: file.name,
      result: result,
    ),
  );
  if (saved != null && saved > 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Imported $saved historical demand '
          '${saved == 1 ? 'record' : 'records'}.',
        ),
      ),
    );
  }
  return saved ?? 0;
}

/// A CSV file's rows as plain text. Handles quoted cells, including commas
/// and doubled quotes inside them.
List<List<String>> readCsvTable(String content) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;

  void endCell() {
    row.add(cell.toString().trim());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  // A leading byte-order mark is not part of the first header.
  final text = content.startsWith('﻿') ? content.substring(1) : content;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endCell();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(char);
    }
  }
  endRow();
  return rows;
}

/// The first sheet of an Excel file, as plain text.
List<List<String>> readXlsxTable(Uint8List bytes) {
  final workbook = Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) return [];
  final sheet = workbook.tables[workbook.tables.keys.first]!;
  return [
    for (final row in sheet.rows)
      [for (final cell in row) _cellText(cell?.value)],
  ];
}

String _cellText(CellValue? value) => switch (value) {
  null => '',
  TextCellValue v => v.value.toString().trim(),
  IntCellValue v => v.value.toString(),
  DoubleCellValue v => v.value.toString(),
  DateCellValue v => v.asDateTimeLocal().toIso8601String(),
  DateTimeCellValue v => v.asDateTimeLocal().toIso8601String(),
  BoolCellValue v => v.value.toString(),
  FormulaCellValue v => v.formula,
  _ => value.toString(),
};

class _HistoricalDemandPreviewDialog extends StatefulWidget {
  final AdminPalette palette;
  final String fileName;
  final HistoricalDemandImportResult result;

  const _HistoricalDemandPreviewDialog({
    required this.palette,
    required this.fileName,
    required this.result,
  });

  @override
  State<_HistoricalDemandPreviewDialog> createState() =>
      _HistoricalDemandPreviewDialogState();
}

class _HistoricalDemandPreviewDialogState
    extends State<_HistoricalDemandPreviewDialog> {
  bool _saving = false;
  String? _saveError;

  static const _columns = [
    ...HistoricalDemandService.requiredColumns,
    ...HistoricalDemandService.optionalColumns,
  ];

  Future<void> _confirm() async {
    final records = widget.result.validRecords;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await HistoricalDemandService.save(records);
      if (mounted) Navigator.of(context).pop(records.length);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError =
            'Could not save the records. Nothing was imported. '
            '(${error.toString().contains('permission') ? 'Permission denied — the historical_demand rules may not be deployed yet.' : 'Check your connection and try again.'})';
      });
    }
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final result = widget.result;
    final valid = result.validRecords.length;
    final invalid = result.invalidCount;
    final unreadable = result.missingColumns.isNotEmpty;

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import Historical Demand Data',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.fileName} · Review before saving. Valid rows are '
                'saved as historical demand records only — no orders are '
                'created.',
                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              if (unreadable)
                _missingColumns(c, result.missingColumns)
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('$valid valid', c.green),
                    if (invalid > 0) _chip('$invalid with errors', c.red),
                    _chip('${result.rows.length} rows read', c.textSecondary),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(child: _table(c, result.rows)),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _saveError!,
                  style: TextStyle(color: c.red, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!unreadable && invalid > 0)
                    Expanded(
                      child: Text(
                        'Rows with errors are skipped. Fix them in the file '
                        'and import it again to add them.',
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, 0),
                    child: Text(unreadable ? 'Close' : 'Cancel'),
                  ),
                  if (!unreadable) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: valid == 0 || _saving ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: adminActionColor(c),
                        foregroundColor: adminOnActionColor(c),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        elevation: 0,
                        textStyle: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(
                        _saving
                            ? 'Saving…'
                            : 'Import $valid valid '
                                  '${valid == 1 ? 'row' : 'rows'}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingColumns(AdminPalette c, List<String> missing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.redBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This file cannot be imported: required '
            '${missing.length == 1 ? 'column is' : 'columns are'} missing.',
            style: TextStyle(
              color: c.red,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Missing: ${missing.join(', ')}',
            style: TextStyle(color: c.textPrimary, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Required columns: '
            '${HistoricalDemandService.requiredColumns.join(', ')}. '
            'Optional: '
            '${HistoricalDemandService.optionalColumns.join(', ')}. '
            'The first row must be the column titles.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _table(AdminPalette c, List<HistoricalDemandImportRow> rows) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'The file has column titles but no rows of data.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }
    // Rows with errors first, so they cannot be missed in a long file.
    final ordered = [
      ...rows.where((r) => !r.isValid),
      ...rows.where((r) => r.isValid),
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: AdminTableFit(
          table: DataTable(
            headingRowColor: WidgetStateProperty.all(adminTableHeaderColor(c)),
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 76,
            columnSpacing: kAdminTableColumnSpacing,
            horizontalMargin: kAdminTableMargin,
            headingTextStyle: adminTableHeaderStyle(c),
            dataTextStyle: TextStyle(
              fontFamily: kAdminFontFamily,
              color: c.textPrimary,
              fontSize: 12.5,
            ),
            columns: [
              const DataColumn(label: Text('Row')),
              for (final column in _columns) DataColumn(label: Text(column)),
              const DataColumn(label: Text('Result')),
            ],
            rows: [for (final row in ordered) _row(c, row)],
          ),
        ),
      ),
    );
  }

  DataRow _row(AdminPalette c, HistoricalDemandImportRow row) {
    final record = row.record;
    // A valid row shows its normalized values — what will be saved.
    final values = record == null
        ? row.raw
        : {
            'Year': '${record.year}',
            'Month': '${record.month}',
            'Commodity': record.commodity,
            'Category': record.category,
            'Quantity Sold': _trim(record.quantity),
            'Unit': record.unit,
            'Average Price': record.averagePrice == null
                ? ''
                : _trim(record.averagePrice!),
            'Location': record.location,
            'Source': record.source,
          };
    return DataRow(
      color: record == null ? WidgetStateProperty.all(c.redBg) : null,
      cells: [
        DataCell(
          Text('${row.rowNumber}', style: TextStyle(color: c.textSecondary)),
        ),
        for (final column in _columns)
          DataCell(
            Text((values[column] ?? '').isEmpty ? '—' : values[column]!),
          ),
        DataCell(
          record != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: c.green),
                    const SizedBox(width: 6),
                    Text('Ready', style: TextStyle(color: c.green)),
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    row.errors.join(' '),
                    style: TextStyle(color: c.red, fontSize: 12),
                  ),
                ),
        ),
      ],
    );
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}
