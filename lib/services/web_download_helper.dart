import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a real browser file download for arbitrary bytes — the same
/// Blob + anchor(download) + synthetic click mechanism the `printing`
/// package already uses internally for `Printing.sharePdf` on web, just
/// exposed here for the formats it doesn't cover (Excel, CSV/zip, PNG).
class WebDownloadHelper {
  const WebDownloadHelper._();

  static void download(Uint8List bytes, String filename, String mimeType) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
