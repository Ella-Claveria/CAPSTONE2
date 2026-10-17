import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'report_section.dart';

/// Builds the Export Report's .xlsx workbook: a Summary sheet first (the
/// report's particulars, its findings and a list of the sheets), then one
/// sheet per section.
///
/// Every sheet is laid out the same way — a title block, a dark green
/// header row, quietly banded rows, a Total row set apart in bold — and
/// amounts, counts and percentages are written as real numbers in peso,
/// whole-number and percent formats, so they can be added up, sorted and
/// charted in Excel.
class ExcelReportService {
  const ExcelReportService._();

  static final _green = ExcelColor.fromHexString('FF1B5E20');
  static final _ink = ExcelColor.fromHexString('FF1F2A22');
  static final _muted = ExcelColor.fromHexString('FF66706A');
  static final _rule = ExcelColor.fromHexString('FFDDE3DC');
  static final _band = ExcelColor.fromHexString('FFF6F8F4');
  static final _totalFill = ExcelColor.fromHexString('FFEAF1E4');

  static const _peso = CustomNumericNumFormat(formatCode: '"₱"#,##0.00');
  static const _percent = CustomNumericNumFormat(formatCode: '0.0%');
  static const _whole = CustomNumericNumFormat(formatCode: '#,##0');

  static final RegExp _pesoText = RegExp(r'^₱\s?(-?[\d,]+(?:\.\d+)?)$');
  static final RegExp _percentText = RegExp(r'^(-?\d+(?:\.\d+)?)%$');

  /// The workbook. [title], [period], [preparedBy] and [generatedAt] head
  /// every sheet; [findings] are listed on the Summary sheet.
  static Uint8List build(
    List<ReportSection> sections, {
    String title = 'AgriTrade+ Analytics Report',
    String? period,
    String? preparedBy,
    DateTime? generatedAt,
    List<String> findings = const [],
    // More particulars for the Summary sheet (the Audit Log's filters).
    List<(String, String)> details = const [],
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final generated = generatedAt ?? DateTime.now();

    // Sheet names: 31 characters at most, none of [ ] : * ? / \, and no
    // two the same. A long title with a part in brackets ("Transactions
    // (Sep 16 – Oct 15, 2026)") loses that part rather than being cut.
    final used = <String>{'Summary'};
    String sheetNameFor(String sectionTitle) {
      var cleaned = sectionTitle.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
      final bracket = cleaned.indexOf(' (');
      if (cleaned.length > 31 && bracket > 0) cleaned = cleaned.substring(0, bracket);
      if (cleaned.length > 31) cleaned = cleaned.substring(0, 31);
      var name = cleaned;
      for (var n = 2; used.contains(name); n++) {
        final suffix = ' ($n)';
        name = '${cleaned.substring(0, math.min(cleaned.length, 31 - suffix.length))}$suffix';
      }
      used.add(name);
      return name;
    }

    final sheetNames = [for (final section in sections) sheetNameFor(section.title)];

    if (defaultSheet != null) excel.rename(defaultSheet, 'Summary');
    _summarySheet(
      excel['Summary'],
      title: title,
      period: period,
      preparedBy: preparedBy,
      generatedAt: generated,
      findings: findings,
      details: details,
      contents: [for (var i = 0; i < sections.length; i++) (sheetNames[i], sections[i].title)],
    );

    for (var i = 0; i < sections.length; i++) {
      _sectionSheet(
        excel[sheetNames[i]],
        sections[i],
        number: i + 1,
        title: title,
        period: period,
        generatedAt: generated,
      );
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? const []);
  }

  // ============================================================
  // SHEETS
  // ============================================================

  static void _summarySheet(
    Sheet sheet, {
    required String title,
    required String? period,
    required String? preparedBy,
    required DateTime generatedAt,
    required List<String> findings,
    required List<(String, String)> details,
    required List<(String sheet, String section)> contents,
  }) {
    var row = 0;
    _put(sheet, 0, row, TextCellValue('AgriTrade+'),
        CellStyle(bold: true, fontSize: 16, fontColorHex: _green));
    _put(sheet, 3, row, TextCellValue('Agricultural Marketplace Platform'),
        CellStyle(italic: true, fontSize: 9, fontColorHex: _muted, horizontalAlign: HorizontalAlign.Right));
    sheet.setRowHeight(row, 26);
    row++;
    _rule3(sheet, row, 4);
    row += 2;

    _put(sheet, 0, row, TextCellValue(title), CellStyle(bold: true, fontSize: 14, fontColorHex: _ink));
    sheet.setRowHeight(row, 22);
    row += 2;

    final particulars = [
      ('Reporting period', period ?? 'All time'),
      ...details,
      if (preparedBy != null && preparedBy.isNotEmpty) ('Prepared by', preparedBy),
      ('Date generated', _dateTime(generatedAt)),
      ('Reference', _reference(generatedAt)),
    ];
    for (final (label, value) in particulars) {
      _put(sheet, 0, row, TextCellValue(label),
          CellStyle(bold: true, fontSize: 10, fontColorHex: _muted, bottomBorder: _thin(_rule)));
      _put(sheet, 1, row, TextCellValue(value),
          CellStyle(fontSize: 10, fontColorHex: _ink));
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
      row++;
    }
    row++;

    if (findings.isNotEmpty) {
      row = _heading(sheet, row, 'Summary of Findings', span: 4);
      for (var i = 0; i < findings.length; i++) {
        // The number and the statement in one cell across the sheet.
        _put(sheet, 0, row, TextCellValue('${i + 1}.   ${findings[i]}'),
            CellStyle(fontSize: 10, fontColorHex: _ink, textWrapping: TextWrapping.WrapText,
                verticalAlign: VerticalAlign.Top));
        sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
            CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        // Room for a finding that wraps onto a second line.
        sheet.setRowHeight(row, findings[i].length > 120 ? 30 : 17);
        row++;
      }
      row++;
    }

    row = _heading(sheet, row, 'Contents', span: 4);
    for (var i = 0; i < contents.length; i++) {
      _put(sheet, 0, row, TextCellValue('${i + 1}   ${contents[i].$2}'),
          CellStyle(fontSize: 10, fontColorHex: _ink));
      sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
      _put(sheet, 3, row, TextCellValue('Sheet: ${contents[i].$1}'),
          CellStyle(italic: true, fontSize: 9, fontColorHex: _muted));
      row++;
    }

    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 40);
    sheet.setColumnWidth(2, 30);
    sheet.setColumnWidth(3, 34);
  }

  static void _sectionSheet(
    Sheet sheet,
    ReportSection section, {
    required int number,
    required String title,
    required String? period,
    required DateTime generatedAt,
  }) {
    final columns = math.max(section.headers.length, 1);
    final span = math.max(columns, 3);

    // Not merged: the lines run on to the right over the empty cells, so a
    // narrow table does not cut them short.
    _put(sheet, 0, 0, TextCellValue(title.contains('AgriTrade+') ? title : 'AgriTrade+  ·  $title'),
        CellStyle(bold: true, fontSize: 9, fontColorHex: _green));
    _put(sheet, 0, 1, TextCellValue('$number   ${section.title}'),
        CellStyle(bold: true, fontSize: 14, fontColorHex: _ink));
    sheet.setRowHeight(1, 24);
    _put(sheet, 0, 2,
        TextCellValue('Reporting period: ${period ?? 'All time'}    ·    Generated ${_dateTime(generatedAt)}'),
        CellStyle(fontSize: 9, fontColorHex: _muted));
    _rule3(sheet, 3, span);

    const headerRow = 5;
    if (section.rows.isEmpty) {
      _put(sheet, 0, headerRow, TextCellValue('No data for this period.'),
          CellStyle(italic: true, fontSize: 10, fontColorHex: _muted));
      sheet.setColumnWidth(0, 30);
      return;
    }

    // Which columns hold figures (right-aligned) and dates (centred, so a
    // figure beside them does not run into them), header included.
    bool every(int c, bool Function(Object?) test) =>
        section.rows.any((r) => c < r.length && test(r[c])) &&
        section.rows.every((r) => c >= r.length || test(r[c]) || _isBlank(r[c]));
    final figure = [for (var c = 0; c < columns; c++) c > 0 && every(c, _isFigure)];
    final date = [for (var c = 0; c < columns; c++) c > 0 && every(c, _isDate)];
    HorizontalAlign alignFor(int c) => figure[c]
        ? HorizontalAlign.Right
        : (date[c] ? HorizontalAlign.Center : HorizontalAlign.Left);

    for (var c = 0; c < columns; c++) {
      _put(
        sheet,
        c,
        headerRow,
        TextCellValue(section.headers[c]),
        CellStyle(
          bold: true,
          fontSize: 10,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: _green,
          horizontalAlign: alignFor(c),
          verticalAlign: VerticalAlign.Center,
          bottomBorder: _thin(_green),
        ),
      );
    }
    sheet.setRowHeight(headerRow, 22);

    final widths = [for (var c = 0; c < columns; c++) section.headers[c].length.toDouble()];
    for (var r = 0; r < section.rows.length; r++) {
      final values = section.rows[r];
      final isTotal = values.isNotEmpty && values.first == 'Total';
      final fill = isTotal ? _totalFill : (r.isOdd ? _band : ExcelColor.none);
      for (var c = 0; c < columns; c++) {
        final raw = c < values.length ? values[c] : null;
        final (value, format) = _cell(raw);
        _put(
          sheet,
          c,
          headerRow + 1 + r,
          value,
          CellStyle(
            bold: isTotal,
            fontSize: 10,
            fontColorHex: _ink,
            backgroundColorHex: fill,
            horizontalAlign: alignFor(c),
            verticalAlign: VerticalAlign.Center,
            numberFormat: format,
            topBorder: isTotal ? _medium(_green) : null,
            bottomBorder: _thin(_rule),
          ),
        );
        widths[c] = math.max(widths[c], (raw?.toString() ?? '').length.toDouble());
      }
      sheet.setRowHeight(headerRow + 1 + r, 18);
    }

    // Columns as wide as their longest entry, within reason.
    for (var c = 0; c < columns; c++) {
      sheet.setColumnWidth(c, (widths[c] * 1.15 + 4).clamp(c == 0 ? 18 : 12, 60).toDouble());
    }
  }

  // ============================================================
  // PIECES
  // ============================================================

  static void _put(Sheet sheet, int column, int row, CellValue? value, CellStyle style) {
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row), value, cellStyle: style);
  }

  // A heading row with a green rule under it; returns the next row.
  static int _heading(Sheet sheet, int row, String text, {required int span}) {
    for (var c = 0; c < span; c++) {
      _put(sheet, c, row, c == 0 ? TextCellValue(text) : null,
          CellStyle(bold: true, fontSize: 12, fontColorHex: _ink, bottomBorder: _medium(_green)));
    }
    sheet.setRowHeight(row, 20);
    return row + 1;
  }

  // The letterhead rule: a green line across [span] columns.
  static void _rule3(Sheet sheet, int row, int span) {
    for (var c = 0; c < span; c++) {
      _put(sheet, c, row, null, CellStyle(topBorder: _thick(_green)));
    }
    sheet.setRowHeight(row, 6);
  }

  static Border _thin(ExcelColor color) => Border(borderStyle: BorderStyle.Thin, borderColorHex: color);
  static Border _medium(ExcelColor color) => Border(borderStyle: BorderStyle.Medium, borderColorHex: color);
  static Border _thick(ExcelColor color) => Border(borderStyle: BorderStyle.Thick, borderColorHex: color);

  static bool _isBlank(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == '—' || text == 'No data' || text == 'New';
  }

  // "Sep 1, 2026", "Oct 13, 2026 – 9:05 AM" and the like.
  static final RegExp _dateText = RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}\b');

  static bool _isDate(Object? value) => _dateText.hasMatch(value?.toString().trim() ?? '');

  static bool _isFigure(Object? value) {
    if (value is num) return true;
    final text = value?.toString().trim() ?? '';
    return _pesoText.hasMatch(text) ||
        _percentText.hasMatch(text) ||
        RegExp(r'^₱\s?[\d,]+(\.\d+)?/.+$').hasMatch(text);
  }

  /// A report value as a cell: a number with its format when it is one
  /// (₱ amounts, percentages, counts), the text itself otherwise.
  static (CellValue?, NumFormat) _cell(Object? value) {
    if (value == null) return (null, NumFormat.standard_0);
    if (value is int) return (IntCellValue(value), _whole);
    if (value is num) {
      return value == value.roundToDouble()
          ? (IntCellValue(value.toInt()), _whole)
          : (DoubleCellValue(value.toDouble()), NumFormat.standard_4);
    }
    final text = value.toString().trim();
    final peso = _pesoText.firstMatch(text);
    if (peso != null) {
      final amount = double.tryParse(peso.group(1)!.replaceAll(',', ''));
      if (amount != null) return (DoubleCellValue(amount), _peso);
    }
    final percent = _percentText.firstMatch(text);
    if (percent != null) {
      final share = double.tryParse(percent.group(1)!);
      if (share != null) return (DoubleCellValue(share / 100), _percent);
    }
    return (TextCellValue(value.toString()), NumFormat.standard_0);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dateTime(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    return '${_months[at.month - 1]} ${at.day}, ${at.year}, $hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _reference(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'AT-${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}';
  }
}
