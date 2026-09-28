// Common entry point for triggering a file download/save across platforms.
// Shared code should import this file (never `web_download_helper.dart` or
// `web_download_helper_io.dart` directly) — the conditional export below
// swaps in the web implementation (`dart:js_interop` + `package:web`) only
// when actually compiling for the web; every other platform gets the
// `file_picker`-based implementation instead, since `dart:js_interop` isn't
// available outside a web compile target.
export 'web_download_helper_io.dart' if (dart.library.js_interop) 'web_download_helper.dart';
