import '../../../core/network/api_client.dart';
import 'auth_models.dart';

/// Repository/service architecture (architecture §4/§10): the ONLY thing
/// that calls the network layer for authentication. An interface, not just
/// a concrete class, specifically so `AuthController` (the Riverpod state
/// machine) can be tested against a fake implementation with no real HTTP
/// call — see test/features/auth/auth_controller_test.dart.
abstract class AuthRepository {
  Future<AuthSession> login({required String phone, required String password});
  Future<RefreshedTokens> refresh(String refreshToken);
  Future<void> logout(String? refreshToken);
  Future<AuthIdentity> me();
  Future<void> changePassword({required String currentPassword, required String newPassword});
}

/// The real implementation — routes to `/api/auth/*` or `/api/admin/auth/*`
/// depending on `accountType`, mirroring the backend's two separate
/// identity tables/routers exactly (architecture §11).
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client, {required this.accountType});

  final ApiClient _client;
  final AccountType accountType;

  String get _basePath => accountType == AccountType.businessUser ? '/auth' : '/admin/auth';

  @override
  Future<AuthSession> login({required String phone, required String password}) async {
    final json = await _client.postJson('$_basePath/login', {'phone': phone, 'password': password});
    return AuthSession.fromJson(json);
  }

  @override
  Future<RefreshedTokens> refresh(String refreshToken) async {
    final json = await _client.postJson('$_basePath/refresh', {'refreshToken': refreshToken});
    return RefreshedTokens.fromJson(json);
  }

  @override
  Future<void> logout(String? refreshToken) async {
    await _client.postJson('$_basePath/logout', {'refreshToken': ?refreshToken});
  }

  @override
  Future<AuthIdentity> me() async {
    final json = await _client.getJson('$_basePath/me');
    return AuthIdentity.fromJson(json);
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _client.postJson('$_basePath/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }
}
