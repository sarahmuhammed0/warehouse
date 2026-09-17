import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../storage/secure_token_storage.dart';

/// Phase 2 §19: attaches the access token to every request and handles a
/// single, loop-safe refresh-on-401. Registered once, in `main.dart`, onto
/// the app's one shared [ApiClient]'s Dio instance
/// (`core/network/providers.dart`'s `apiClientProvider`) — wiring happens
/// in `main.dart`, not inside `core/network/providers.dart` itself, so
/// that file never has to import anything from `features/auth` (this file
/// does, and `main.dart` — the composition root — is where those two
/// otherwise-separate dependency graphs are allowed to meet).
///
/// Loop safety: a request is retried at most once
/// (`options.extra['retried']`). If the retry ALSO 401s, or the refresh
/// call itself fails, the interceptor gives up, tells [AuthController]
/// the session is over (`handleSessionExpired`), and rejects — it never
/// calls refresh a second time for the same failure. Concurrent 401s
/// share one in-flight refresh via `_refreshing` rather than each
/// triggering their own.
///
/// Never logged: this interceptor does not log request/response bodies or
/// headers anywhere (§19's explicit rule) — Dio's own default logging is
/// not enabled anywhere in this app.
class AuthInterceptor extends Interceptor {
  // The fields below are deliberately private (not part of this class's
  // public API) — Dart's initializing-formal shorthand (`this._storage`)
  // can't be used here since formal parameter names may not start with `_`.
  AuthInterceptor({
    required TokenStorage storage,
    required AuthRepository repository,
    required Future<void> Function() onSessionExpired,
  }) : _storage = storage, // ignore: prefer_initializing_formals
       _repo = repository, // ignore: prefer_initializing_formals
       _onSessionExpired = onSessionExpired; // ignore: prefer_initializing_formals

  final TokenStorage _storage;
  final AuthRepository _repo;
  final Future<void> Function() _onSessionExpired;
  Future<String?>? _refreshing;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    final isAuthEndpoint = err.requestOptions.path.contains('/auth/login') ||
        err.requestOptions.path.contains('/auth/refresh');

    if (!isUnauthorized || alreadyRetried || isAuthEndpoint) {
      return handler.next(err);
    }

    final newAccessToken = await _refreshAccessTokenOnce();
    if (newAccessToken == null) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final retryOptions = err.requestOptions;
    retryOptions.extra['retried'] = true;
    retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';

    try {
      final dio = Dio(BaseOptions(baseUrl: retryOptions.baseUrl));
      final response = await dio.fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Coalesces concurrent 401s from several in-flight requests into ONE
  /// refresh call, not one per request.
  Future<String?> _refreshAccessTokenOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final tokens = await _repo.refresh(refreshToken);
      await _storage.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
      return tokens.accessToken;
    } catch (_) {
      return null;
    }
  }
}

/// Built from the same providers `AuthController` uses, so there is
/// exactly one refresh-token storage and one repository instance in play —
/// attached to the shared Dio instance once, in `main.dart`.
final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  return AuthInterceptor(
    storage: ref.watch(secureTokenStorageProvider),
    repository: ref.watch(authRepositoryProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).handleSessionExpired(),
  );
});
