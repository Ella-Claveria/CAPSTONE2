// The Export Report's PDF: built end to end with key findings, a table
// with its Total row, an empty section and the sign-off, without a layout
// error.
import 'package:agritrade/services/pdf_report_service.dart';
import 'package:agritrade/services/report_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The report's font loader reads the app's asset list.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the dashboard report builds with findings, totals and sign-off',
    () async {
      final bytes = await PdfReportService.buildFullDashboardReport(
        title: 'AgriTrade+ Analytics Report',
        adminName: 'System Administrator',
        generatedAt: DateTime(2026, 10, 16, 9),
        dateRangeLabel: 'Sep 16, 2026 – Oct 15, 2026',
        landscape: false,
        includeDataTables: true,
        keyFindings: const [
          'Completed sales reached ₱1,200.00 from 3 orders.',
          'Top category: Grains, with ₱900.00 (75.0% of sales).',
        ],
        sections: const [
          ReportSection(
            title: 'Sales by Category',
            headers: ['Category', 'Revenue', 'Share of Sales'],
            rows: [
              ['Grains', '₱900.00', '75.0%'],
              ['Vegetables', '₱300.00', '25.0%'],
              ['Total', '₱1,200.00', '100%'],
            ],
          ),
          ReportSection(
            title: 'Top-Selling Products',
            headers: ['Product', 'Quantity Sold', 'Revenue', 'Share of Sales'],
            rows: [],
          ),
        ],
      );
      // A real PDF document.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );
}
