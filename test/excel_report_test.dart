// The Export Report's Excel workbook: a Summary sheet first, then one sheet
// per section, with amounts and percentages written as real numbers.
import 'package:agritrade/services/excel_report_service.dart';
import 'package:agritrade/services/report_section.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Summary sheet first, and figures saved as numbers', () {
    final bytes = ExcelReportService.build(
      const [
        ReportSection(
          title: 'Sales by Category',
          headers: ['Category', 'Revenue', 'Share of Sales'],
          rows: [
            ['Grains', '₱2,900.00', '59.7%'],
            ['Total', '₱2,900.00', '100%'],
          ],
        ),
        ReportSection(
          title: 'Price Trend vs. Baseline',
          headers: ['Commodity', 'Week'],
          rows: [],
        ),
      ],
      period: 'Sep 16, 2026 – Oct 15, 2026',
      preparedBy: 'System Administrator',
      generatedAt: DateTime(2026, 10, 16, 9, 28),
      findings: const ['Top category: Grains.'],
    );

    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys.first, 'Summary');
    expect(
      book.tables.keys,
      containsAll(['Sales by Category', 'Price Trend vs. Baseline']),
    );

    final sales = book.tables['Sales by Category']!;
    // A number, whichever kind the file is read back as.
    num? number(String cell) =>
        switch (sales.cell(CellIndex.indexByString(cell)).value) {
          IntCellValue(:final value) => value,
          DoubleCellValue(:final value) => value,
          _ => null,
        };
    // The header row is row 6 (index 5); Grains is the row under it.
    expect(
      sales.cell(CellIndex.indexByString('A6')).value,
      TextCellValue('Category'),
    );
    expect(number('B7'), 2900);
    expect(number('C7'), closeTo(0.597, 1e-9));
    expect(number('C8'), 1);

    final empty = book.tables['Price Trend vs. Baseline']!;
    expect(
      empty.cell(CellIndex.indexByString('A6')).value,
      TextCellValue('No data for this period.'),
    );
  });
}
