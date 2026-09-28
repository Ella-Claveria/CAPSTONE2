import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Mobile/desktop counterpart to `web_download_helper.dart` — same class
/// name and method signature, selected instead of it by
/// `download_helper.dart`'s conditional export whenever `dart:js_interop`
/// isn't available (i.e. everywhere except Flutter Web). Uses the
/// cross-platform save dialog `file_picker` already ships (native "Save As"
/// on desktop, Storage Access Framework on Android) rather than a browser
/// download, since there's no browser here to download into.
class WebDownloadHelper {
  const WebDownloadHelper._();

  static void download(Uint8List bytes, String filename, String mimeType) {
    FilePicker.saveFile(fileName: filename, bytes: bytes, mimeType: mimeType);
  }
}
