import 'dart:typed_data';

import '../error/failure.dart';

/// Every platform except the web, where there is no browser to hand a file to.
///
/// Refuses rather than pretending. A desktop or mobile build wanting this would
/// need a file picker and a real path, which is a platform integration, not a
/// fallback that can be guessed at here.
Future<void> downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  throw const Failure(
    'DOWNLOAD_UNSUPPORTED',
    'Saving a file is only supported in the browser build.',
  );
}
