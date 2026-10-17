/// One exportable dashboard section's data, already formatted into a
/// header row + data rows — built by ReportExportService from the exact
/// same DashboardAnalyticsService numbers the live dashboard shows.
/// Format-agnostic on purpose: ExcelReportService, CsvReportService, and
/// PdfReportService all consume this same shape, so "what goes in each
/// section" is decided once instead of drifting across three builders.
class ReportSection {
  final String title;
  final List<String> headers;
  final List<List<Object?>> rows; // String, num, or null per cell

  /// How much of the width each column takes in the PDF, relative to the
  /// others (a long "Details" column wider than a date). Null: the first
  /// column a little wider, the rest even.
  final List<double>? columnWeights;

  const ReportSection({
    required this.title,
    required this.headers,
    required this.rows,
    this.columnWeights,
  });
}
