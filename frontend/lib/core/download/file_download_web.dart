import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser download: wrap the bytes in a Blob, point an anchor at it, and
/// click it.
///
/// The object URL is revoked immediately afterwards. It is a reference into
/// this tab's memory holding the whole file — leaving one per download alive
/// keeps every invoice the user ever opened in memory for the life of the tab.
Future<void> downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
