import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../screen/export_options_dialog.dart' show ReportFormat;
import 'audit_log_service.dart';
import 'csv_report_service.dart';
import 'download_helper.dart';
import 'excel_report_service.dart';
import 'pdf_report_service.dart';
import 'report_section.dart';

/// A column the Audit Log report's detailed log can show, with the share
/// of the PDF's width it takes.
enum AuditReportColumn {
  dateTime('Date & Time', 1.65),
  admin('Admin', 1.5),
  action('Action', 1.3),
  details('Details', 2.7),
  device('Device / Browser', 1.25),
  location('Location', 1.2);

  final String label;
  final double weight;
  const AuditReportColumn(this.label, this.weight);
}

/// A part of the Audit Log report the Admin can leave in or out.
enum AuditReportPart {
  summary('Activity summary', 'How many of each action, with key findings'),
  byAdmin(
    'Activity by admin',
    'How many entries each admin has, and when they were last active',
  ),
  log('Detailed log', 'Every entry, with the columns chosen below');

  final String label;
  final String description;
  const AuditReportPart(this.label, this.description);
}

/// One Audit Log entry as the report shows it.
class AuditReportRow {
  final DateTime? at;
  final String admin;
  // The recorded action ("LOGIN_FAILED") and how it reads ("Login Failed").
  final String actionCode;
  final String action;
  final String details;
  final String device;
  final String location;

  const AuditReportRow({
    required this.at,
    required this.admin,
    required this.actionCode,
    required this.action,
    required this.details,
    required this.device,
    required this.location,
  });

  String get when =>
      at == null ? '—' : DateFormat('MMM d, y – h:mm a').format(at!);

  Object? value(AuditReportColumn column) => switch (column) {
    AuditReportColumn.dateTime => when,
    AuditReportColumn.admin => admin,
    AuditReportColumn.action => action,
    AuditReportColumn.details => details.isEmpty ? '—' : details,
    AuditReportColumn.device => device,
    AuditReportColumn.location => location,
  };
}

/// What the Admin chose in the Audit Log's Export Report menu.
class AuditReportOptions {
  final ReportFormat format;
  final Set<AuditReportPart> parts;
  final List<AuditReportColumn> columns;
  final bool landscape;
  final String remarks;

  const AuditReportOptions({
    required this.format,
    required this.parts,
    required this.columns,
    this.landscape = true,
    this.remarks = '',
  });
}

/// The Audit Log's report: the entries the Admin chose, laid out in the
/// parts and columns they chose, as the same PDF, Excel and CSV documents
/// the Dashboard's Export Report produces.
class AuditReportService {
  const AuditReportService._();

  static const String title = 'Admin Portal Audit Log';

  /// Builds the report and hands it over (the share sheet for a PDF, a
  /// download otherwise). Returns the file's name.
  static Future<String> export({
    required List<AuditReportRow> rows,
    required AuditReportOptions options,
    required String periodLabel,
    required String filtersLabel,
    required String scopeLabel,
    void Function(String step)? onProgress,
  }) async {
    final now = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;
    final preparedBy = user?.displayName ?? user?.email ?? 'Admin';
    final sections = buildSections(rows, options);
    final findings = options.parts.contains(AuditReportPart.summary)
        ? buildFindings(rows)
        : const <String>[];
    final entries =
        '${NumberFormat('#,##0').format(rows.length)} (${scopeLabel.toLowerCase()})';
    final base = 'AgriTrade_Audit_Log_${DateFormat('yyyy-MM-dd').format(now)}';

    onProgress?.call(
      options.format == ReportFormat.pdf
          ? 'Building the PDF…'
          : 'Building the file…',
    );
    late final Uint8List bytes;
    late final String filename;
    switch (options.format) {
      case ReportFormat.pdf:
        bytes = await PdfReportService.buildFullDashboardReport(
          title: title,
          kind: 'Audit Log Report',
          adminName: preparedBy,
          generatedAt: now,
          dateRangeLabel: periodLabel,
          notes: options.remarks,
          landscape: options.landscape,
          includeDataTables: true,
          keyFindings: findings,
          sections: sections,
          particulars: [
            ('Reporting period', periodLabel),
            ('Filters applied', filtersLabel),
            ('Entries', entries),
            ('Date generated', DateFormat('MMM d, y · h:mm a').format(now)),
          ],
        );
        filename = '$base.pdf';
      case ReportFormat.excel:
        bytes = ExcelReportService.build(
          sections,
          title: title,
          period: periodLabel,
          preparedBy: preparedBy,
          generatedAt: now,
          findings: findings,
          details: [('Filters applied', filtersLabel), ('Entries', entries)],
        );
        filename = '$base.xlsx';
      case ReportFormat.csv:
      case ReportFormat.png:
        final csv = CsvReportService.build(sections);
        bytes = csv.bytes;
        filename = '$base.${csv.extension}';
    }

    onProgress?.call('Saving the file…');
    switch (options.format) {
      case ReportFormat.pdf:
        await PdfReportService.share(bytes, filename);
      case ReportFormat.excel:
        WebDownloadHelper.download(
          bytes,
          filename,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case ReportFormat.csv:
      case ReportFormat.png:
        WebDownloadHelper.download(
          bytes,
          filename,
          filename.endsWith('.zip') ? 'application/zip' : 'text/csv',
        );
    }

    AuditLogService.log(
      AuditAction.exportReport,
      'Exported the Audit Log (${options.format.name.toUpperCase()}), ${rows.length} '
      '${rows.length == 1 ? 'entry' : 'entries'}, $periodLabel; '
      '${options.parts.map((p) => p.label).join(', ')}.',
    );
    return filename;
  }

  /// The report's tables, in the order chosen parts appear: the activity
  /// summary, activity by admin, then the detailed log.
  static List<ReportSection> buildSections(
    List<AuditReportRow> rows,
    AuditReportOptions options,
  ) {
    final sections = <ReportSection>[];

    if (options.parts.contains(AuditReportPart.summary)) {
      final byAction = <String, int>{};
      for (final row in rows) {
        byAction[row.action] = (byAction[row.action] ?? 0) + 1;
      }
      final sorted = byAction.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      sections.add(
        ReportSection(
          title: 'Activity Summary',
          headers: const ['Action', 'Entries', 'Share of Entries'],
          rows: [
            for (final e in sorted)
              [e.key, e.value, _share(e.value, rows.length)],
            if (sorted.isNotEmpty) ['Total', rows.length, '100%'],
          ],
        ),
      );
    }

    if (options.parts.contains(AuditReportPart.byAdmin)) {
      final count = <String, int>{};
      final last = <String, DateTime>{};
      for (final row in rows) {
        count[row.admin] = (count[row.admin] ?? 0) + 1;
        final at = row.at;
        if (at != null &&
            (last[row.admin] == null || at.isAfter(last[row.admin]!))) {
          last[row.admin] = at;
        }
      }
      final sorted = count.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      sections.add(
        ReportSection(
          title: 'Activity by Admin',
          headers: const [
            'Admin',
            'Entries',
            'Share of Entries',
            'Last Activity',
          ],
          rows: [
            for (final e in sorted)
              [
                e.key,
                e.value,
                _share(e.value, rows.length),
                last[e.key] == null
                    ? '—'
                    : DateFormat('MMM d, y – h:mm a').format(last[e.key]!),
              ],
            if (sorted.isNotEmpty) ['Total', rows.length, '100%', '—'],
          ],
        ),
      );
    }

    if (options.parts.contains(AuditReportPart.log)) {
      final columns = options.columns.isEmpty
          ? [AuditReportColumn.dateTime]
          : options.columns;
      sections.add(
        ReportSection(
          title: 'Detailed Log',
          headers: [for (final c in columns) c.label],
          rows: [
            for (final row in rows) [for (final c in columns) row.value(c)],
          ],
          columnWeights: [for (final c in columns) c.weight],
        ),
      );
    }
    return sections;
  }

  /// A few plain statements on the entries: how many, logins that failed,
  /// the most active admin and the most frequent action.
  static List<String> buildFindings(List<AuditReportRow> rows) {
    if (rows.isEmpty) return const ['No audit log entries match this report.'];
    final findings = <String>[];
    final dated = [
      for (final r in rows)
        if (r.at != null) r.at!,
    ]..sort();
    findings.add(
      '${NumberFormat('#,##0').format(rows.length)} '
      '${rows.length == 1 ? 'entry was' : 'entries were'} recorded'
      '${dated.isEmpty ? '' : ' between ${DateFormat('MMM d, y').format(dated.first)} and ${DateFormat('MMM d, y').format(dated.last)}'}.',
    );

    final ok = rows
        .where((r) => r.actionCode == AuditAction.loginSuccess)
        .length;
    final failed = rows
        .where((r) => r.actionCode == AuditAction.loginFailed)
        .length;
    if (ok > 0 || failed > 0) {
      findings.add(
        '$ok successful ${ok == 1 ? 'login' : 'logins'} and '
        '${failed == 0 ? 'no failed login attempts' : '$failed failed login ${failed == 1 ? 'attempt' : 'attempts'}'}.',
      );
    }

    String? topOf(Iterable<String> keys) {
      final counts = <String, int>{};
      for (final k in keys) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
      if (counts.isEmpty) return null;
      final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
      return '${top.key} (${top.value} ${top.value == 1 ? 'entry' : 'entries'})';
    }

    final admin = topOf(
      rows
          .map((r) => r.admin)
          .where((a) => !a.startsWith('Attempt:') && a != 'Unknown'),
    );
    if (admin != null) findings.add('Most active admin: $admin.');
    final action = topOf(rows.map((r) => r.action));
    if (action != null) findings.add('Most frequent action: $action.');
    return findings;
  }

  static String _share(int part, int whole) =>
      whole <= 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)}%';
}
