import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'report_section.dart';

/// Builds CSV output for the Export flow — a single .csv when only one
/// section is selected, or a .zip (one .csv per section) when more than
/// one is, since a single CSV can't represent multiple independent tables.
class CsvReportService {
  const CsvReportService._();

  static String _escapeField(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String buildCsv(ReportSection section) {
    final buffer = StringBuffer();
    if (section.rows.isEmpty) {
      buffer.writeln('No data for this period');
      return buffer.toString();
    }
    buffer.writeln(section.headers.map(_escapeField).join(','));
    for (final row in section.rows) {
      buffer.writeln(row.map(_escapeField).join(','));
    }
    return buffer.toString();
  }

  static String _fileSafeName(String title) =>
      title.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// Returns the bytes to download plus the extension to save them with —
  /// ".csv" for one section, ".zip" (containing one .csv per section) for
  /// more than one.
  static ({Uint8List bytes, String extension}) build(List<ReportSection> sections) {
    if (sections.length == 1) {
      final bytes = Uint8List.fromList(utf8.encode(buildCsv(sections.first)));
      return (bytes: bytes, extension: 'csv');
    }

    final archive = Archive();
    for (final section in sections) {
      final csvBytes = utf8.encode(buildCsv(section));
      archive.addFile(ArchiveFile('${_fileSafeName(section.title)}.csv', csvBytes.length, csvBytes));
    }
    final zipped = ZipEncoder().encode(archive);
    return (bytes: Uint8List.fromList(zipped ?? const []), extension: 'zip');
  }
}
