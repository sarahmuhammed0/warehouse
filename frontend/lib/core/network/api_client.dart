import 'package:dio/dio.dart';

import '../config/env.dart';
import '../error/failure.dart';

/// API layer foundation (architecture §27/§29's Flutter equivalent of
/// `services/httpClient.js`). Every feature's repository calls through this
/// — nothing constructs its own `Dio` instance. It unwraps the backend's
/// standard `{ success, data }` / `{ success, error }` envelope exactly
/// once, here, so repositories only ever deal with plain data or a
/// [Failure], never with HTTP/Dio types directly.
class ApiClient {
  ApiClient({Dio? dio})
    : dio = dio ??
          Dio(
            BaseOptions(
              baseUrl: Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

  /// Exposed (not private) so `core/network/auth_interceptor.dart` can
  /// attach itself in `main.dart` — the interceptor needs the same Dio
  /// instance every request goes through, not a second one.
  final Dio dio;

  Future<Map<String, dynamic>> getJson(String path) => _unwrap(dio.get<Map<String, dynamic>>(path));

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) =>
      _unwrap(dio.post<Map<String, dynamic>>(path, data: body));

  /// For list endpoints, whose envelope is shaped differently: `data` is an
  /// ARRAY and the paging block lives under `meta.pagination`. [getJson]
  /// cannot serve these — it casts `data` to a Map, which for an array
  /// yields null and would silently hand back an empty list rather than
  /// failing. Returns both halves so a repository can build a
  /// `PaginatedResult` without re-parsing the envelope.
  Future<({List<dynamic> data, Map<String, dynamic> meta})> getList(String path) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(path);
      final body = response.data;

      if (body == null || body['success'] != true) {
        throw _failureFrom(body, response.statusCode);
      }

      return (
        data: (body['data'] as List<dynamic>?) ?? const [],
        meta: (body['meta'] as Map<String, dynamic>?) ?? const {},
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        throw _failureFrom(data, e.response?.statusCode);
      }
      throw Failure.network();
    }
  }

  Future<Map<String, dynamic>> _unwrap(Future<Response<Map<String, dynamic>>> request) async {
    try {
      final response = await request;
      final body = response.data;

      if (body == null || body['success'] != true) {
        throw _failureFrom(body, response.statusCode);
      }

      return (body['data'] as Map<String, dynamic>?) ?? const {};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        throw _failureFrom(data, e.response?.statusCode);
      }
      throw Failure.network();
    }
  }

  Failure _failureFrom(Map<String, dynamic>? body, int? statusCode) {
    final error = body?['error'] as Map<String, dynamic>?;
    return Failure(
      (error?['code'] as String?) ?? 'REQUEST_FAILED',
      (error?['message'] as String?) ?? 'Request failed (${statusCode ?? 'unknown'}).',
    );
  }
}
