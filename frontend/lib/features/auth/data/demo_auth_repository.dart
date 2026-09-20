import 'auth_models.dart';
import 'auth_repository.dart';

/// One-click demo credentials the login screen's demo buttons pass to
/// `AuthController.login()` — recognized only inside this file, never
/// exposed as a real account anywhere else. Not secret (this is a local
/// frontend-testing feature, not a security boundary) — the phone strings
/// are deliberately implausible (`0000000`) so they can never collide with
/// a real E.164 number, and the manual login form still accepts them if
/// typed by hand.
///
/// Nine identities total: System Admin, plus one per business role (spec
/// §23) — `kDemoBusinessPhone` (the original Business Owner/Admin demo)
/// through `kDemoViewerPhone`. Each business-role phone matches an
/// `Employee.phone` seeded in `employee_repository.dart`, which is how
/// `permission_providers.dart` resolves a real, distinct role/permission
/// set per identity rather than every demo login getting owner-level
/// access (see docs/roles-and-permissions.md §I).
const String kDemoBusinessPhone = '+9647000000001';
const String kDemoAdminPhone = '+9647000000002';
const String kDemoManagerPhone = '+9647000000003';
const String kDemoWarehouseManagerPhone = '+9647000000004';
const String kDemoSalesStaffPhone = '+9647000000005';
const String kDemoInventoryStaffPhone = '+9647000000006';
const String kDemoProductionManagerPhone = '+9647000000007';
const String kDemoAccountantPhone = '+9647000000008';
const String kDemoViewerPhone = '+9647000000009';
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
  String _currentBusinessPhone = kDemoBusinessPhone;

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

  /// One account per business role, same demo business (`businessBusiness`)
  /// — a role is a property of the *person*, not the business, so these
  /// deliberately don't get separate `AuthBusiness` records.
  static const Map<String, AuthAccount> _businessAccountsByPhone = {
    kDemoBusinessPhone: businessAccount,
    kDemoManagerPhone: AuthAccount(id: -3, name: 'Zana Hussein', phone: kDemoManagerPhone),
    kDemoWarehouseManagerPhone: AuthAccount(id: -4, name: 'Rezan Ali', phone: kDemoWarehouseManagerPhone),
    kDemoSalesStaffPhone: AuthAccount(id: -5, name: 'Dilan Omar', phone: kDemoSalesStaffPhone),
    kDemoInventoryStaffPhone: AuthAccount(id: -6, name: 'Ary Karim', phone: kDemoInventoryStaffPhone),
    kDemoProductionManagerPhone: AuthAccount(id: -7, name: 'Soran Najat', phone: kDemoProductionManagerPhone),
    kDemoAccountantPhone: AuthAccount(id: -8, name: 'Lana Faraj', phone: kDemoAccountantPhone),
    kDemoViewerPhone: AuthAccount(id: -9, name: 'Hero Salih', phone: kDemoViewerPhone),
  };

  Future<void> _settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.value();
    }
  }

  bool _isAdminPhone(String phone) => phone.trim() == kDemoAdminPhone;

  String _accessTokenFor(String phone) => 'demo-access-token-$phone';
  String _refreshTokenFor(String phone) => 'demo-refresh-token-$phone';

  @override
  Future<AuthSession> login({required String phone, required String password}) async {
    await _settle();
    final trimmed = phone.trim();
    if (_isAdminPhone(trimmed)) {
      _currentType = AccountType.systemAdmin;
      return AuthSession(accessToken: _accessTokenFor(kDemoAdminPhone), refreshToken: _refreshTokenFor(kDemoAdminPhone), account: adminAccount);
    }
    _currentType = AccountType.businessUser;
    // An unrecognized phone (e.g. typed by hand into the real form while in
    // demo mode) still succeeds, as it always has — falls back to the
    // original Business Owner/Admin identity rather than rejecting it.
    _currentBusinessPhone = _businessAccountsByPhone.containsKey(trimmed) ? trimmed : kDemoBusinessPhone;
    return AuthSession(
      accessToken: _accessTokenFor(_currentBusinessPhone),
      refreshToken: _refreshTokenFor(_currentBusinessPhone),
      account: _businessAccountsByPhone[_currentBusinessPhone]!,
      business: businessBusiness,
    );
  }

  @override
  Future<RefreshedTokens> refresh(String refreshToken) async {
    await _settle();
    if (refreshToken == _refreshTokenFor(kDemoAdminPhone)) {
      _currentType = AccountType.systemAdmin;
      return RefreshedTokens(accessToken: _accessTokenFor(kDemoAdminPhone), refreshToken: _refreshTokenFor(kDemoAdminPhone));
    }
    _currentType = AccountType.businessUser;
    final matchedPhone = _businessAccountsByPhone.keys.firstWhere(
      (phone) => refreshToken == _refreshTokenFor(phone),
      orElse: () => kDemoBusinessPhone,
    );
    _currentBusinessPhone = matchedPhone;
    return RefreshedTokens(accessToken: _accessTokenFor(matchedPhone), refreshToken: _refreshTokenFor(matchedPhone));
  }

  @override
  Future<void> logout(String? refreshToken) => _settle();

  @override
  Future<AuthIdentity> me() async {
    await _settle();
    return _currentType == AccountType.systemAdmin
        ? const AuthIdentity(account: adminAccount)
        : AuthIdentity(account: _businessAccountsByPhone[_currentBusinessPhone]!, business: businessBusiness);
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) => _settle();
}
