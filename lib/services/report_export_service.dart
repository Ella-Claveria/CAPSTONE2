import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screen/export_options_dialog.dart' show ReportFormat, DashboardSection;
import '../widgets/chart_capture_boundary.dart';
import 'audit_log_service.dart';
import 'csv_report_service.dart';
import 'dashboard_analytics_service.dart';
import 'excel_report_service.dart';
import 'market_price_helpers.dart';
import 'pdf_report_service.dart';
import 'download_helper.dart';
import 'report_section.dart';

class ExportResult {
  final String filename;
  final List<String> missingDataSections;
  const ExportResult({required this.filename, required this.missingDataSections});
}

/// Orchestrates the Export Report dialog: fetches real Firestore data once
/// (not streams — this is a one-shot action), re-runs the exact same
/// DashboardAnalyticsService logic the live dashboard uses for whichever
/// date range was chosen, builds the sections for the chosen format,
/// captures chart images where relevant, triggers the browser download,
/// and logs the export to the Audit Log.
class ReportExportService {
  const ReportExportService._();

  static GlobalKey? _keyFor(DashboardSection s) => switch (s) {
        DashboardSection.salesOverview => DashboardChartKeys.salesOverview,
        DashboardSection.salesByCategory => DashboardChartKeys.salesByCategory,
        DashboardSection.priceTrend => DashboardChartKeys.priceTrend,
        DashboardSection.newRegistrations => DashboardChartKeys.registrations,
        DashboardSection.verificationStatus => DashboardChartKeys.verificationStatus,
        _ => null,
      };

  static Future<ExportResult> export({
    required ReportFormat format,
    required Set<DashboardSection> sections,
    required Set<String> selectedCommodities,
    required DateTimeRange? range,
    required String reportTitle,
    required bool landscape,
    required bool includeDataTables,
    required String notes,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final results = await Future.wait([
      firestore.collection('users').get(),
      firestore.collection('verificationDocs').get(),
      firestore.collection('orders').where('status', isEqualTo: 'completed').get(),
      firestore.collection('market_prices').get(),
      firestore.collection('products').get(),
    ]);
    final userDocs = results[0].docs;
    final verifDocs = results[1].docs;
    final orders = results[2].docs;
    final priceDocs = results[3].docs;
    final products = results[4].docs;
    final usersByUid = <String, Map<String, dynamic>>{for (final d in userDocs) d.id: d.data()};
    final now = DateTime.now();

    if (format == ReportFormat.png) {
      return _exportPng(sections: sections, range: range);
    }

    final missing = <String>[];
    final reportSections = <ReportSection>[];
    final chartImages = <String, Uint8List>{};

    // Dashboard order, exactly as the live page renders it.
    for (final section in DashboardSection.values) {
      if (!sections.contains(section)) continue;

      final built = switch (section) {
        DashboardSection.kpiSummary => _kpiSummary(userDocs, orders, range),
        DashboardSection.salesOverview => _salesOverview(orders, range),
        DashboardSection.salesByCategory => _salesByCategory(orders, products, range),
        DashboardSection.priceTrend =>
          _priceTrend(orders, priceDocs, selectedCommodities, now, range),
        DashboardSection.topSellingProducts => _topProducts(orders, range),
        DashboardSection.demandByBarangay => _demandByBarangay(orders, usersByUid, now, range),
        DashboardSection.newRegistrations => _registrations(userDocs, now, range),
        DashboardSection.verificationStatus => _verificationStatus(userDocs),
        DashboardSection.liveCommodityPrices => _livePrices(priceDocs),
        DashboardSection.recentVerificationRequests =>
          _recentVerifications(verifDocs, usersByUid, range),
      };
      reportSections.add(built);
      if (built.rows.isEmpty) missing.add(built.title);

      if (format == ReportFormat.pdf && section.isChart) {
        final key = _keyFor(section);
        if (key != null) {
          final image = await ChartCaptureBoundary.captureFrom(key);
          if (image != null) chartImages[built.title] = image;
        }
      }
    }

    final rangeLabel = range == null
        ? 'All time'
        : '${DateFormat('MMM d, y').format(range.start)} – ${DateFormat('MMM d, y').format(range.end)}';
    final adminName =
        FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email ?? 'Admin';
    final baseName = _fileBaseName(range);

    late final Uint8List bytes;
    late final String extension;
    late final String mimeType;

    switch (format) {
      case ReportFormat.pdf:
        bytes = await PdfReportService.buildFullDashboardReport(
          title: reportTitle,
          adminName: adminName,
          generatedAt: now,
          dateRangeLabel: rangeLabel,
          notes: notes,
          landscape: landscape,
          includeDataTables: includeDataTables,
          sections: reportSections,
          chartImages: chartImages,
        );
        extension = 'pdf';
        mimeType = 'application/pdf';
      case ReportFormat.excel:
        bytes = ExcelReportService.build(reportSections);
        extension = 'xlsx';
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ReportFormat.csv:
        final csv = CsvReportService.build(reportSections);
        bytes = csv.bytes;
        extension = csv.extension;
        mimeType = extension == 'zip' ? 'application/zip' : 'text/csv';
      case ReportFormat.png:
        throw StateError('handled above');
    }

    final filename = 'AgriTrade_Analytics_$baseName.$extension';
    if (format == ReportFormat.pdf) {
      await PdfReportService.share(bytes, filename);
    } else {
      WebDownloadHelper.download(bytes, filename, mimeType);
    }

    AuditLogService.log(
      AuditAction.exportReport,
      'Exported the Dashboard Overview report (${_formatName(format)}), $rangeLabel, '
      'sections: ${sections.map((s) => s.label).join(', ')}.',
    );

    return ExportResult(filename: filename, missingDataSections: missing);
  }

  static Future<ExportResult> _exportPng({
    required Set<DashboardSection> sections,
    required DateTimeRange? range,
  }) async {
    final images = <String, Uint8List>{};
    final missing = <String>[];
    for (final section in sections.where((s) => s.isChart)) {
      final key = _keyFor(section);
      final image = key == null ? null : await ChartCaptureBoundary.captureFrom(key);
      if (image != null) {
        images[section.label] = image;
      } else {
        missing.add(section.label);
      }
    }

    final baseName = _fileBaseName(range);
    final String filename;
    if (images.isEmpty) {
      throw StateError('None of the selected charts could be captured — try again after they finish loading.');
    } else if (images.length == 1) {
      final entry = images.entries.first;
      filename = 'AgriTrade_${_fileSafe(entry.key)}_$baseName.png';
      WebDownloadHelper.download(entry.value, filename, 'image/png');
    } else {
      final archive = Archive();
      for (final entry in images.entries) {
        archive.addFile(ArchiveFile('${_fileSafe(entry.key)}.png', entry.value.length, entry.value));
      }
      final zipped = ZipEncoder().encode(archive);
      filename = 'AgriTrade_Charts_$baseName.zip';
      WebDownloadHelper.download(Uint8List.fromList(zipped ?? const []), filename, 'application/zip');
    }

    AuditLogService.log(
      AuditAction.exportReport,
      'Exported Dashboard chart images (PNG): ${sections.map((s) => s.label).join(', ')}.',
    );

    return ExportResult(filename: filename, missingDataSections: missing);
  }

  static String _fileSafe(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static String _fileBaseName(DateTimeRange? range) {
    if (range == null) return DateFormat('yyyy-MM-dd').format(DateTime.now());
    final f = DateFormat('yyyy-MM-dd');
    return '${f.format(range.start)}_to_${f.format(range.end)}';
  }

  static String _formatName(ReportFormat f) => switch (f) {
        ReportFormat.pdf => 'PDF',
        ReportFormat.excel => 'Excel',
        ReportFormat.csv => 'CSV',
        ReportFormat.png => 'PNG',
      };

  // ============================================================
  // SECTION BUILDERS — each mirrors exactly what the live dashboard card
  // shows, via DashboardAnalyticsService, for the chosen [range] (null for
  // the snapshot sections that don't take one).
  // ============================================================

  static ReportSection _kpiSummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final farmerCount = DashboardAnalyticsService.farmerCount(users);
    final buyerCount = DashboardAnalyticsService.buyerCount(users);
    final pending = DashboardAnalyticsService.pendingVerifications(users);
    final total = DashboardAnalyticsService.platformTransactionTotal(orders, range: range);
    return ReportSection(
      title: 'KPI Summary',
      headers: const ['Metric', 'Value', 'Scope'],
      rows: [
        ['Total Users', farmerCount + buyerCount, 'Current snapshot'],
        ['Farmers', farmerCount, 'Current snapshot'],
        ['Buyers', buyerCount, 'Current snapshot'],
        ['Pending Verifications', pending, 'Current snapshot'],
        ['Total Transaction Value', formatPeso(total), 'Selected date range'],
      ],
    );
  }

  static ReportSection _salesOverview(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final bars = range == null
        ? const <({String label, num value})>[]
        : DashboardAnalyticsService.salesBarsForRange(orders, range);
    return ReportSection(
      title: 'Sales Overview',
      headers: const ['Period', 'Revenue'],
      rows: bars.map((b) => [b.label, formatPeso(b.value)]).toList(),
    );
  }

  static ReportSection _salesByCategory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    DateTimeRange? range,
  ) {
    final revenue = DashboardAnalyticsService.categoryRevenue(orders, products, range: range);
    return ReportSection(
      title: 'Sales by Category',
      headers: const ['Category', 'Revenue'],
      rows: revenue.entries.map((e) => [e.key, formatPeso(e.value)]).toList(),
    );
  }

  static ReportSection _priceTrend(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> priceDocs,
    Set<String> selectedCommodities,
    DateTime now,
    DateTimeRange? range,
  ) {
    final rows = <List<Object?>>[];
    for (final doc in priceDocs) {
      final data = doc.data();
      final name = (data['name'] ?? doc.id).toString();
      if (!selectedCommodities.contains(name)) continue;
      final baseline = (data['baselinePrice'] as num?)?.toDouble() ?? 0;
      final weekly = DashboardAnalyticsService.weeklyAveragePrice(orders, name, now: now, range: range);
      for (var i = 0; i < weekly.length; i++) {
        final price = weekly[i];
        rows.add([name, 'Week ${i + 1}', price == null ? 'No data' : formatPeso(price), formatPeso(baseline)]);
      }
    }
    return ReportSection(
      title: 'Price Trend vs. Baseline',
      headers: const ['Commodity', 'Week', 'Average Price', 'Baseline Price'],
      rows: rows,
    );
  }

  static ReportSection _topProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    DateTimeRange? range,
  ) {
    final products = DashboardAnalyticsService.topSellingProducts(orders, limit: 100, range: range);
    return ReportSection(
      title: 'Top-Selling Products',
      headers: const ['Product', 'Quantity Sold', 'Revenue'],
      rows: products.map((p) => [p.name, p.quantity, formatPeso(p.revenue)]).toList(),
    );
  }

  static ReportSection _demandByBarangay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    Map<String, Map<String, dynamic>> usersByUid,
    DateTime now,
    DateTimeRange? range,
  ) {
    final demand = DashboardAnalyticsService.demandByBuyerBarangay(orders, usersByUid, now, range: range);
    return ReportSection(
      title: 'Demand by Barangay',
      headers: const ['Barangay', 'Orders', 'Revenue'],
      rows: demand.map((d) => [d.barangay, d.orderCount, formatPeso(d.revenue)]).toList(),
    );
  }

  static ReportSection _registrations(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    DateTime now,
    DateTimeRange? range,
  ) {
    final regs = DashboardAnalyticsService.registrationsByMonth(users, now, range: range);
    return ReportSection(
      title: 'New Registrations',
      headers: const ['Month', 'Farmers', 'Buyers'],
      rows: regs.map((r) => [r.label, r.farmers, r.buyers]).toList(),
    );
  }

  static ReportSection _verificationStatus(List<QueryDocumentSnapshot<Map<String, dynamic>>> users) {
    final counts = DashboardAnalyticsService.verificationStatusCounts(users);
    return ReportSection(
      title: 'Verification Status',
      headers: const ['Status', 'Count'],
      rows: [
        ['Approved', counts.approved],
        ['Rejected', counts.rejected],
        ['Pending', counts.pending],
      ],
    );
  }

  static ReportSection _livePrices(List<QueryDocumentSnapshot<Map<String, dynamic>>> priceDocs) {
    final prices = DashboardAnalyticsService.commodityPrices(priceDocs);
    return ReportSection(
      title: 'Live Commodity Prices',
      headers: const ['Commodity', 'Current Price', 'Previous Price', 'Change %', 'Last Updated'],
      rows: prices
          .map((p) => [
                p.name,
                formatPeso(p.currentPrice),
                p.previousPrice == null ? '—' : formatPeso(p.previousPrice!),
                p.changePct == null ? 'New' : '${p.changePct!.toStringAsFixed(1)}%',
                p.updatedAt == null ? '—' : DateFormat('MMM d, y').format(p.updatedAt!),
              ])
          .toList(),
    );
  }

  static ReportSection _recentVerifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> verifDocs,
    Map<String, Map<String, dynamic>> usersByUid,
    DateTimeRange? range,
  ) {
    final rows = DashboardAnalyticsService.recentVerifications(verifDocs, usersByUid, range: range, limit: null);
    return ReportSection(
      title: 'Recent Verification Requests',
      headers: const ['Farmer ID', 'Full Name', 'Barangay', 'Date Submitted', 'Status'],
      rows: rows.map((v) => [v.farmerId, v.fullName, v.barangay, v.dateSubmitted, v.status]).toList(),
    );
  }
}
