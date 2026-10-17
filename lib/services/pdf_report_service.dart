import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'market_price_helpers.dart';
import 'report_section.dart';

/// Builds and hands off real PDF reports for the admin dashboard — the
/// system's only "export" used to be a CSV string copied to the clipboard.
/// Generation (pdf package) and delivery (printing package's native share
/// sheet — save to Files, email, etc.) are kept separate so a report can be
/// generated once and either shared or, later, previewed/printed.
///
/// Every report is laid out as the same formal document: a letterhead with
/// the AgriTrade+ logo on the first page and a slim running header on the
/// rest, the title and its particulars, numbered sections, ruled tables
/// (figures right-aligned, a Total row set apart), and a footer with the
/// report's name and page number.
class PdfReportService {
  static const _brandGreen = PdfColor.fromInt(0xFF1B5E20);
  // The yellow of the logo's top edge, for the thin second rule under the
  // letterhead and the bar beside the findings.
  static const _accent = PdfColor.fromInt(0xFFD4A72C);
  static const _ink = PdfColor.fromInt(0xFF1F2A22);
  static const _muted = PdfColor.fromInt(0xFF66706A);
  static const _rule = PdfColor.fromInt(0xFFDDE3DC);
  static const _zebra = PdfColor.fromInt(0xFFF6F8F4);
  static const _totalFill = PdfColor.fromInt(0xFFEAF1E4);

  // Montserrat, as in the portal — and because the pdf package's built-in
  // Helvetica only covers Latin-1: it has no peso sign, which then prints
  // as an empty box. Taken from the app's own font files (so a report can
  // be made offline), from Google Fonts if those cannot be read. Loaded
  // once and kept; a failed load is tried again on the next report.
  static Future<pw.ThemeData?>? _themeLoad;

  // True once a font that has the peso sign is in use.
  static bool _fullFont = false;

  static Future<pw.ThemeData?> _theme() => _themeLoad ??= () async {
        try {
          final base = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-Regular.ttf'));
          final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-SemiBold.ttf'));
          _fullFont = true;
          return pw.ThemeData.withFont(base: base, bold: bold);
        } catch (_) {
          // Not bundled in this build: fetch it instead.
        }
        try {
          final base = await PdfGoogleFonts.montserratRegular();
          final semiBold = await PdfGoogleFonts.montserratSemiBold();
          // The printing package hands back Helvetica when it cannot fetch
          // the font; only a real TrueType font has the peso sign.
          _fullFont = base is pw.TtfFont && semiBold is pw.TtfFont;
          if (!_fullFont) _themeLoad = null;
          return pw.ThemeData.withFont(base: base, bold: semiBold);
        } catch (_) {
          _fullFont = false;
          _themeLoad = null;
          return null;
        }
      }();

  // The AgriTrade+ logo for the letterhead; null if it cannot be read, in
  // which case the letterhead carries the name alone.
  static Future<pw.ImageProvider?>? _logoLoad;

  static Future<pw.ImageProvider?> _logo() => _logoLoad ??= () async {
        try {
          final data = await rootBundle.load('assets/images/logo_report.png');
          return pw.MemoryImage(data.buffer.asUint8List());
        } catch (_) {
          _logoLoad = null;
          return null;
        }
      }();

  // Without that font: "PHP" for the peso sign, and "?" for anything else
  // Helvetica cannot draw — readable, instead of a box.
  static String _safe(String text) {
    if (_fullFont) return text;
    return String.fromCharCodes(
      text.replaceAll('₱', 'PHP ').runes.map((r) => r > 0xFF ? 0x3F : r),
    );
  }

  static String _reference(DateTime at) => 'AT-${DateFormat('yyyyMMdd-HHmm').format(at)}';

  // ============================================================
  // PAGE FRAME — letterhead, running header, footer
  // ============================================================

  /// One report as a run of pages: the letterhead on the first, a slim
  /// header on the rest, and the footer on all of them.
  static pw.MultiPage _pages({
    required PdfPageFormat format,
    required pw.ImageProvider? logo,
    required String kind,
    required String title,
    required String period,
    required DateTime generatedAt,
    required List<pw.Widget> Function(pw.Context context) build,
  }) {
    return pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(42, 34, 42, 30),
      header: (context) => context.pageNumber == 1
          ? _letterhead(logo, kind, generatedAt)
          : _runningHeader(logo, title, period),
      footer: (context) => _footer(context, title, period),
      build: build,
    );
  }

  static pw.Widget _letterhead(pw.ImageProvider? logo, String kind, DateTime generatedAt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 42, height: 42),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('AgriTrade+',
                    style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _brandGreen)),
                pw.SizedBox(height: 1),
                pw.Text('Agricultural Marketplace Platform',
                    style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              ],
            ),
            pw.Spacer(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(kind.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink, letterSpacing: 1.2)),
                pw.SizedBox(height: 2),
                pw.Text('Ref. ${_reference(generatedAt)}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2.2, color: _brandGreen),
        pw.SizedBox(height: 1.5),
        pw.Container(height: 0.8, color: _accent),
        pw.SizedBox(height: 18),
      ],
    );
  }

  static pw.Widget _runningHeader(pw.ImageProvider? logo, String title, String period) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          if (logo != null) ...[
            pw.Image(logo, width: 13, height: 13),
            pw.SizedBox(width: 6),
          ],
          pw.Text(_safe(title), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _brandGreen)),
          pw.Spacer(),
          pw.Text(_safe(period), style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context, String title, String period) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Text(_safe('$title  ·  $period'), style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          pw.Spacer(),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
        ],
      ),
    );
  }

  // ============================================================
  // CONTENT PIECES
  // ============================================================

  /// The report's title, and its particulars in a ruled row of labelled
  /// fields (period, who prepared it, when).
  static pw.Widget _titleBlock(String title, List<(String, String)> particulars) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(_safe(title), style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: _rule, width: 0.6),
              bottom: pw.BorderSide(color: _rule, width: 0.6),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < particulars.length; i++) ...[
                if (i > 0) pw.SizedBox(width: 18),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(particulars[i].$1.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 7, fontWeight: pw.FontWeight.bold, color: _muted, letterSpacing: 0.9)),
                      pw.SizedBox(height: 3),
                      pw.Text(_safe(particulars[i].$2), style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 18),
      ],
    );
  }

  /// A section's heading: its number in the brand green, then its name,
  /// over a hairline.
  static pw.Widget _sectionHeading(String title, {int? number}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (number != null)
            pw.SizedBox(
              width: 20,
              child: pw.Text('$number',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _brandGreen)),
            ),
          pw.Expanded(
            child: pw.Text(_safe(title),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
          ),
        ],
      ),
    );
  }

  /// The Summary of Findings: numbered statements beside a thin bar in
  /// the logo's yellow.
  static pw.Widget _findings(List<String> findings) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _accent, width: 2.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < findings.length; i++)
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: i == findings.length - 1 ? 0 : 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 16,
                    child: pw.Text('${i + 1}.',
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _brandGreen)),
                  ),
                  pw.Expanded(
                    child: pw.Text(_safe(findings[i]),
                        style: const pw.TextStyle(fontSize: 9.5, color: _ink, lineSpacing: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // A cell that holds a figure — an amount, a count, a percentage — and is
  // therefore right-aligned.
  static final RegExp _figure = RegExp(r'^(₱|PHP\s?)?-?[\d,]+(\.\d+)?\s?%?(/.+)?$');

  static bool _isFigureColumn(List<List<String>> rows, int column) {
    var seen = false;
    for (final row in rows) {
      if (column >= row.length) continue;
      final cell = row[column].trim();
      if (cell.isEmpty || cell == '—' || cell == 'No data' || cell == 'New') continue;
      if (!_figure.hasMatch(cell)) return false;
      seen = true;
    }
    return seen;
  }

  /// A ruled table: a dark green header row (repeated on every page the
  /// table runs onto), quiet alternating rows, figures right-aligned, and
  /// a "Total" row set apart in bold over a green rule.
  static pw.Widget _table(List<String> headers, List<List<String>> rows, {List<double>? weights}) {
    if (rows.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule, width: 0.6)),
        child: pw.Text('No data for this period.', style: const pw.TextStyle(fontSize: 9, color: _muted)),
      );
    }
    final figures = [for (var c = 0; c < headers.length; c++) c > 0 && _isFigureColumn(rows, c)];
    pw.Alignment align(int c) => figures[c] ? pw.Alignment.centerRight : pw.Alignment.centerLeft;

    pw.Widget cell(String text, int c, pw.TextStyle style) => pw.Container(
          alignment: align(c),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: pw.Text(_safe(text), style: style, textAlign: figures[c] ? pw.TextAlign.right : pw.TextAlign.left),
        );

    final headerStyle = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    const bodyStyle = pw.TextStyle(fontSize: 9, color: _ink);
    final totalStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink);

    return pw.Table(
      columnWidths: weights != null && weights.length == headers.length
          ? {for (var c = 0; c < headers.length; c++) c: pw.FlexColumnWidth(weights[c])}
          : {
              // The first column (the name of each row) gets more room.
              0: const pw.FlexColumnWidth(1.6),
              for (var c = 1; c < headers.length; c++) c: const pw.FlexColumnWidth(1),
            },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _brandGreen),
          children: [for (var c = 0; c < headers.length; c++) cell(headers[c], c, headerStyle)],
        ),
        for (var r = 0; r < rows.length; r++)
          () {
            final isTotal = rows[r].isNotEmpty && rows[r].first == 'Total';
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: isTotal ? _totalFill : (r.isOdd ? _zebra : null),
                border: isTotal
                    ? const pw.Border(top: pw.BorderSide(color: _brandGreen, width: 0.9))
                    : const pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.5)),
              ),
              children: [
                for (var c = 0; c < headers.length; c++)
                  cell(c < rows[r].length ? rows[r][c] : '', c, isTotal ? totalStyle : bodyStyle),
              ],
            );
          }(),
      ],
    );
  }

  /// The sign-off at the end of a report: Prepared by (the Admin who made
  /// it), Noted by and Approved by, each with a line for the signature
  /// over the printed name, and the date. Kept together on one page.
  static pw.Widget _signOff(String preparedBy) {
    pw.Widget block(String role, String? name) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(role, style: const pw.TextStyle(fontSize: 9, color: _muted)),
              pw.SizedBox(height: 30),
              // The same height with or without a name, so the three
              // signature lines are level.
              pw.Container(
                width: double.infinity,
                height: 16,
                alignment: pw.Alignment.bottomCenter,
                padding: const pw.EdgeInsets.only(bottom: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.7)),
                ),
                child: name == null
                    ? pw.SizedBox()
                    : pw.Text(
                        _safe(name),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink),
                      ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text('Signature over printed name', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Date: ____________________', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        );

    return pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 14),
          _sectionHeading('Certification'),
          pw.Text(
            'The figures in this report were generated from the AgriTrade+ records on the date shown above.',
            style: const pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              block('Prepared by:', preparedBy),
              pw.SizedBox(width: 26),
              block('Noted by:', null),
              pw.SizedBox(width: 26),
              block('Approved by:', null),
            ],
          ),
        ],
      ),
    );
  }

  // Tables up to this many rows (of short text) are kept on one page with
  // their heading — few enough to fit even a landscape page.
  static const int _keepTogetherRows = 12;

  static String _generatedLabel(DateTime at) => DateFormat('MMM d, y · h:mm a').format(at);

  // ============================================================
  // REPORTS
  // ============================================================

  /// The Demand Heatmap screen's report: completed-order demand grouped
  /// by buyer location, plus the top buyer search terms — the same two
  /// datasets the old CSV export covered, now as an actual PDF.
  static Future<Uint8List> buildDemandReport({
    required List<({String barangay, int orderCount, num revenue})> demand,
    required List<MapEntry<String, int>> topSearches,
    String? periodLabel,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final logo = await _logo();
    final now = DateTime.now();
    final period = periodLabel ?? 'All time';
    doc.addPage(
      _pages(
        format: PdfPageFormat.a4,
        logo: logo,
        kind: 'Market Demand Report',
        title: 'Market Demand Report',
        period: period,
        generatedAt: now,
        build: (context) => [
          _titleBlock('Market Demand Report', [
            ('Reporting period', period),
            ('Coverage', 'Completed orders by buyer location'),
            ('Date generated', _generatedLabel(now)),
          ]),
          _sectionHeading('Demand by Area', number: 1),
          _table(
            ['Area', 'Completed Orders', 'Revenue'],
            demand.map((d) => [d.barangay, '${d.orderCount}', formatPeso(d.revenue)]).toList(),
          ),
          pw.SizedBox(height: 20),
          _sectionHeading('Top Buyer Searches', number: 2),
          _table(
            ['Search Term', 'Count'],
            topSearches.map((e) => [e.key, '${e.value}']).toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// The Export Report dialog's PDF output — every selected Analytics
  /// Dashboard section, in dashboard order, built from the exact same
  /// DashboardAnalyticsService numbers shown on screen (see
  /// ReportExportService, which assembles [sections] and [chartImages]).
  /// A section with no [chartImages] entry (PNG capture unavailable, or
  /// the section isn't chart-backed) always falls back to its data table;
  /// [includeDataTables] additionally shows the table *under* a captured
  /// chart image too.
  static Future<Uint8List> buildFullDashboardReport({
    required String title,
    required String adminName,
    required DateTime generatedAt,
    required String dateRangeLabel,
    String? notes,
    required bool landscape,
    required bool includeDataTables,
    // Plain sentences on what the figures say, under the title.
    List<String> keyFindings = const [],
    required List<ReportSection> sections,
    Map<String, Uint8List> chartImages = const {},
    // Charts as raw RGBA pixels (see ChartCaptureBoundary.captureRawFrom);
    // used in preference to a PNG in [chartImages] for the same section.
    Map<String, ({Uint8List rgba, int width, int height})> rawChartImages =
        const {},
    // The kind of report named on the letterhead, and the particulars under
    // the title when not the usual period / prepared by / generated (the
    // Audit Log report adds its filters).
    String kind = 'Analytics Report',
    List<(String, String)>? particulars,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final logo = await _logo();

    final widgets = <pw.Widget>[
      _titleBlock(
        title,
        particulars ??
            [
              ('Reporting period', dateRangeLabel),
              ('Prepared by', adminName),
              ('Date generated', _generatedLabel(generatedAt)),
            ],
      ),
    ];

    if (keyFindings.isNotEmpty) {
      widgets.addAll([
        _sectionHeading('Summary of Findings'),
        _findings(keyFindings),
        pw.SizedBox(height: 20),
      ]);
    }

    if (notes != null && notes.trim().isNotEmpty) {
      widgets.addAll([
        _sectionHeading('Remarks'),
        pw.Text(_safe(notes.trim()), style: const pw.TextStyle(fontSize: 9.5, color: _ink, lineSpacing: 1.5)),
        pw.SizedBox(height: 20),
      ]);
    }

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final raw = rawChartImages[section.title];
      final image = raw != null ? null : chartImages[section.title];
      final showTable = (raw == null && image == null) || includeDataTables;
      final heading = _sectionHeading(section.title, number: i + 1);

      // A short table with no chart stays with its heading: the two move
      // to the next page together rather than the heading being left at
      // the foot of one page. A long table runs on across pages instead.
      // Only a table that surely fits on one page: few rows, none with
      // text long enough to wrap (an unsplittable block taller than a page
      // cannot be laid out at all).
      final compact = section.rows.length <= _keepTogetherRows &&
          section.rows.every((r) => r.every((cell) => (cell?.toString().length ?? 0) <= 48));
      if (raw == null && image == null && compact) {
        // Inseparable: a page break cannot split it (a bare Column can be).
        widgets.add(pw.Inseparable(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              heading,
              _table(
                section.headers,
                section.rows.map((r) => r.map((cell) => cell?.toString() ?? '').toList()).toList(),
                weights: section.columnWeights,
              ),
            ],
          ),
        ));
        widgets.add(pw.SizedBox(height: 20));
        continue;
      }

      widgets.add(heading);
      if (raw != null || image != null) {
        widgets.add(
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule, width: 0.6)),
            child: raw != null
                ? pw.Image(pw.RawImage(bytes: raw.rgba, width: raw.width, height: raw.height),
                    height: 210, fit: pw.BoxFit.contain)
                : pw.Image(pw.MemoryImage(image!), height: 210, fit: pw.BoxFit.contain),
          ),
        );
        widgets.add(pw.SizedBox(height: 10));
      }
      if (showTable) {
        widgets.add(_table(
          section.headers,
          section.rows.map((r) => r.map((cell) => cell?.toString() ?? '').toList()).toList(),
                weights: section.columnWeights,
        ));
      }
      widgets.add(pw.SizedBox(height: 20));
    }

    widgets.add(_signOff(adminName));

    doc.addPage(
      _pages(
        format: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        logo: logo,
        kind: kind,
        title: title,
        period: dateRangeLabel,
        generatedAt: generatedAt,
        build: (context) => widgets,
      ),
    );
    return doc.save();
  }

  /// The Farmer List screen's export — the KPI totals shown above the
  /// table (org-wide, not affected by filters) plus the table exactly as
  /// currently filtered/sorted on screen (see FarmerListView._export).
  static Future<Uint8List> buildFarmerListReport({
    required int totalFarmers,
    required int activeListingsTotal,
    required int completedOrdersTotal,
    required List<
        ({
          String farmerId,
          String fullName,
          String email,
          String barangay,
          String municipality,
          String dateApproved,
          int activeListings,
          int completedOrders,
        })> rows,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final logo = await _logo();
    final now = DateTime.now();
    final shown = '${rows.length} of $totalFarmers approved farmers';
    doc.addPage(
      _pages(
        format: PdfPageFormat.a4.landscape,
        logo: logo,
        kind: 'Farmer List',
        title: 'Farmer List Report',
        period: shown,
        generatedAt: now,
        build: (context) => [
          _titleBlock('Farmer List Report', [
            ('Farmers shown', shown),
            ('Date generated', _generatedLabel(now)),
          ]),
          _sectionHeading('Overview', number: 1),
          _table(
            ['Metric', 'Value'],
            [
              ['Total Farmers', '$totalFarmers'],
              ['Active Listings', '$activeListingsTotal'],
              ['Completed Orders', '$completedOrdersTotal'],
            ],
          ),
          pw.SizedBox(height: 20),
          _sectionHeading('Approved Farmers', number: 2),
          _table(
            [
              'RSBA No.',
              'Full Name',
              'Email',
              'Barangay',
              'Municipality',
              'Date Approved',
              'Active Listings',
              'Completed Orders',
            ],
            rows
                .map((r) => [
                      r.farmerId,
                      r.fullName,
                      r.email,
                      r.barangay,
                      r.municipality,
                      r.dateApproved,
                      '${r.activeListings}',
                      '${r.completedOrders}',
                    ])
                .toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Hands the generated PDF to the OS share sheet — save to Files, email,
  /// send via chat, etc. No storage permission needed since nothing is
  /// written to app-external storage directly.
  static Future<void> share(Uint8List bytes, String filename) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
