// The Audit Log's Export Report: the parts and columns the Admin chooses,
// the findings, and the menu itself.
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/audit_export_dialog.dart';
import 'package:agritrade/screen/export_options_dialog.dart' show ReportFormat;
import 'package:agritrade/services/audit_log_service.dart';
import 'package:agritrade/services/audit_report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

AuditReportRow row(String admin, String code, int day) => AuditReportRow(
  at: DateTime(2026, 10, day, 9),
  admin: admin,
  actionCode: code,
  action: code == AuditAction.loginSuccess
      ? 'Login Success'
      : (code == AuditAction.loginFailed ? 'Login Failed' : 'Export Report'),
  details: 'details $day',
  device: 'Chrome on Windows',
  location: 'Laurel, PH',
);

final rows = [
  row('System Administrator', AuditAction.loginSuccess, 14),
  row('System Administrator', AuditAction.exportReport, 15),
  row('Attempt: x@y.com', AuditAction.loginFailed, 15),
  row('System Administrator', AuditAction.loginSuccess, 16),
];

void main() {
  test('only the chosen parts, and only the chosen columns', () {
    final sections = AuditReportService.buildSections(
      rows,
      const AuditReportOptions(
        format: ReportFormat.pdf,
        parts: {AuditReportPart.summary, AuditReportPart.log},
        columns: [AuditReportColumn.dateTime, AuditReportColumn.action],
      ),
    );
    expect(sections.map((s) => s.title), ['Activity Summary', 'Detailed Log']);

    final summary = sections.first;
    expect(summary.rows.first, ['Login Success', 2, '50.0%']);
    expect(summary.rows.last, ['Total', 4, '100%']);

    final log = sections.last;
    expect(log.headers, ['Date & Time', 'Action']);
    expect(log.rows, hasLength(4));
    expect(log.columnWeights, hasLength(2));
  });

  test('activity by admin counts entries and the last activity', () {
    final sections = AuditReportService.buildSections(
      rows,
      const AuditReportOptions(
        format: ReportFormat.excel,
        parts: {AuditReportPart.byAdmin},
        columns: [],
      ),
    );
    final byAdmin = sections.single;
    expect(byAdmin.rows.first[0], 'System Administrator');
    expect(byAdmin.rows.first[1], 3);
    expect(byAdmin.rows.first[3], 'Oct 16, 2026 – 9:00 AM');
  });

  test('the findings', () {
    final findings = AuditReportService.buildFindings(rows);
    expect(
      findings.first,
      '4 entries were recorded between Oct 14, 2026 and Oct 16, 2026.',
    );
    expect(
      findings,
      contains('2 successful logins and 1 failed login attempt.'),
    );
    expect(
      findings,
      contains('Most active admin: System Administrator (3 entries).'),
    );
    expect(AuditReportService.buildFindings(const []), [
      'No audit log entries match this report.',
    ]);
  });

  testWidgets('the Export menu fits a desktop and a phone-sized window', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final size in const [Size(1280, 900), Size(400, 760)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminThemeScope(
            palette: AdminPalette.light,
            child: Scaffold(
              body: AuditExportDialog(
                palette: AdminPalette.light,
                filtersLabel: 'All Activity · Oct 1, 2026 – Oct 16, 2026',
                onScreenCount: 20,
                selectedCount: 0,
                exporter: (_, _, _) async => 'file.pdf',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('Export Audit Log'), findsOneWidget);
      expect(find.text('Detailed log'), findsOneWidget);
      // "Selected entries" cannot be chosen while nothing is ticked.
      expect(find.text('Selected entries (0)'), findsOneWidget);
    }
  });
}
