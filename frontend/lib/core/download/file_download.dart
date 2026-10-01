import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart' as impl;

/// Hands a generated file to the user.
///
/// On the web this is a browser download; there is no filesystem to write to
/// and no viewer to hand a path. Elsewhere it is unsupported and says so
/// rather than failing silently — a save button that appears to work and
/// produces no file is worse than one that explains itself.
///
/// The bytes are fetched with the session's Authorization header by the
/// repository that calls this, which is why the file cannot simply be a link.
Future<void> downloadBytes({
  required Uint8List bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) => impl.downloadBytes(bytes: bytes, filename: filename, mimeType: mimeType);
