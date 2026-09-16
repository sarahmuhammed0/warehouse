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
    : _dio = dio ??
          Dio(
            BaseOptions(
              baseUrl: Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

  final Dio _dio;

  /// GET request that returns the unwrapped `data` payload, or throws a
  /// [Failure] the caller can show directly to the user.
  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      final body = response.data;

      if (body == null || body['success'] != true) {
        final error = body?['error'] as Map<String, dynamic>?;
        throw Failure(
          (error?['code'] as String?) ?? 'REQUEST_FAILED',
          (error?['message'] as String?) ?? 'Request failed (${response.statusCode}).',
        );
      }

      return (body['data'] as Map<String, dynamic>?) ?? const {};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['error'] is Map) {
        final error = data['error'] as Map<String, dynamic>;
        throw Failure(
          (error['code'] as String?) ?? 'REQUEST_FAILED',
          (error['message'] as String?) ?? 'Request failed.',
        );
      }
      throw Failure.network();
    }
  }
}
