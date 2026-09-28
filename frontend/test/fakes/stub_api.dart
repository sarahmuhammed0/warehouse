// A stubbed HTTP layer for testing the real `Api*Repository` classes and the
// screens that read through them.
//
// Dio's adapter is replaced, so nothing leaves the process: each request is
// answered from a map of canned envelopes and recorded, which lets a test
// assert what was SENT as well as what was rendered. Shared by
// `api_repositories_test.dart` (the field mapping) and `api_screens_test.dart`
// (the screens driven by that mapping) so one set of canned shapes serves both.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:warehouse_os_app/core/network/api_client.dart';

/// One recorded call — a request body with the wrong key fails as quietly as a
/// parse, so tests assert on these too.
class StubCall {
  StubCall(this.method, this.path, this.body);
  final String method;
  final String path;
  final Map<String, dynamic>? body;
}

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.responses);

  /// `"METHOD /path"` → the envelope to answer with.
  final Map<String, Map<String, dynamic>> responses;
  final List<StubCall> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data is Map<String, dynamic> ? options.data as Map<String, dynamic> : null;
    calls.add(StubCall(options.method, options.path, body));

    // Matched without the query string: a test cares that the right endpoint
    // was called, and asserts the query separately where it matters.
    final path = options.path.split('?').first;
    final envelope = responses['${options.method} $path'];
    if (envelope == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'error': {'code': 'NOT_STUBBED', 'message': 'No stub for ${options.method} $path'},
        }),
        404,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      jsonEncode(envelope),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

({ApiClient client, StubAdapter stub}) stubbedApi(Map<String, Map<String, dynamic>> responses) {
  final stub = StubAdapter(responses);
  final client = ApiClient();
  client.dio.httpClientAdapter = stub;
  return (client: client, stub: stub);
}

/// The list envelope every paginated endpoint returns (§26/§29).
Map<String, dynamic> listEnvelope(List<Map<String, dynamic>> rows, {int? total}) => {
  'success': true,
  'data': rows,
  'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': total ?? rows.length}},
};

/// The single-object envelope.
Map<String, dynamic> oneEnvelope(Map<String, dynamic> row) => {'success': true, 'data': row};
