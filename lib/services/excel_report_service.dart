import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, BorderStyle;

import 'report_section.dart';

/// Builds a .xlsx workbook with one sheet per section.
class ExcelReportService {
  const ExcelReportService._();

  static CellValue? _cellValue(Object? value) {
    if (value == null) return null;
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }

  static Uint8List build(List<ReportSection> sections) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      // Sheet names can't exceed 31 chars or contain [ ] : * ? / \ —
      // truncate and sanitize rather than letting the package throw on an
      // arbitrary section title.
      final cleaned = section.title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
      final sheetName = cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;

      if (i == 0 && defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }
      final target = excel[sheetName];

      if (section.rows.isEmpty) {
        target.appendRow([TextCellValue('No data for this period')]);
        continue;
      }
      target.appendRow(section.headers.map((h) => TextCellValue(h) as CellValue?).toList());
      for (final row in section.rows) {
        target.appendRow(row.map(_cellValue).toList());
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? const []);
  }
}
