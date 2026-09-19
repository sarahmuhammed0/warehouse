import 'auth_models.dart';
import 'auth_repository.dart';

/// One-click demo credentials the login screen's two demo buttons pass to
/// `AuthController.login()` — recognized only inside this file, never
/// exposed as a real account anywhere else. Not secret (this is a local
/// frontend-testing feature, not a security boundary) — the phone strings
/// are deliberately implausible (`0000000`) so they can never collide with
/// a real E.164 number, and the manual login form still accepts them if
/// typed by hand.
const String kDemoBusinessPhone = '+9647000000001';
const String kDemoAdminPhone = '+9647000000002';
const String kDemoPassword = 'demo';

/// Frontend-only demo authentication (see docs/frontend-demo-mode.md) —
/// implements the exact same `AuthRepository` interface `ApiAuthRepository`
/// does, so `AuthController`/the login screen/route guards need no special
/// case for "am I talking to the real backend." Never calls `ApiClient`,
/// Dio, or any network API — every method resolves from fixed in-memory
/// demo identities. A short artificial delay keeps the loading state
/// (§17/§38 of the auth UI) observable, same reasoning as
/// `core/repositories/demo_data_source.dart`'s `simulatedLatency()` for the
/// business-module repositories, but via microtasks for the same
/// `pumpAndSettle`-safety reason documented there — never a real `Timer`.
class DemoAuthRepository implements AuthRepository {
  AccountType _currentType = AccountType.businessUser;

  static const _businessAccessToken = 'demo-access-token-business';
  static const _businessRefreshToken = 'demo-refresh-token-business';
  static const _adminAccessToken = 'demo-access-token-admin';
  static const _adminRefreshToken = 'demo-refresh-token-admin';

  static const businessAccount = AuthAccount(id: -1, name: 'Demo Owner', phone: kDemoBusinessPhone);
  static const businessBusiness = AuthBusiness(
    id: -1,
    name: 'Demo Furniture Factory',
    businessType: 'furniture_factory',
    logoUrl: null,
    currency: 'USD',
    language: 'en',
    timezone: 'Asia/Baghdad',
    status: 'active',
  );
  static const adminAccount = AuthAccount(id: -2, name: 'Demo System Admin', phone: kDemoAdminPhone);

  Future<void> _settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.value();
    }
  }

  bool _isAdminPhone(String phone) => phone.trim() == kDemoAdminPhone;

  @override
  Future<AuthSession> login({required String phone, required String password}) async {
    await _settle();
    final isAdmin = _isAdminPhone(phone);
    _currentType = isAdmin ? AccountType.systemAdmin : AccountType.businessUser;
    return isAdmin
        ? const AuthSession(accessToken: _adminAccessToken, refreshToken: _adminRefreshToken, account: adminAccount)
        : const AuthSession(
            accessToken: _businessAccessToken,
            refreshToken: _businessRefreshToken,
            account: businessAccount,
            business: businessBusiness,
          );
  }

  @override
  Future<RefreshedTokens> refresh(String refreshToken) async {
    await _settle();
    final isAdmin = refreshToken == _adminRefreshToken;
    _currentType = isAdmin ? AccountType.systemAdmin : AccountType.businessUser;
    return isAdmin
        ? const RefreshedTokens(accessToken: _adminAccessToken, refreshToken: _adminRefreshToken)
        : const RefreshedTokens(accessToken: _businessAccessToken, refreshToken: _businessRefreshToken);
  }

  @override
  Future<void> logout(String? refreshToken) => _settle();

  @override
  Future<AuthIdentity> me() async {
    await _settle();
    return _currentType == AccountType.systemAdmin
        ? const AuthIdentity(account: adminAccount)
        : const AuthIdentity(account: businessAccount, business: businessBusiness);
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) => _settle();
}
