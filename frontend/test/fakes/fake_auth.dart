// Test doubles for the auth feature — no real network, no real platform
// secure-storage channel (unavailable in `flutter_test`'s pure-Dart
// environment). Used to test the LOGIN SCREEN and AUTH CONTROLLER's own
// logic in isolation, and to put already-authenticated/unauthenticated
// fixtures in front of the shell/routing tests without going through a
// real backend. This is legitimate test mocking, not the "fake
// authentication" the architecture rules out (§38) — nothing here ships;
// production `main.dart` always wires the real `ApiAuthRepository` +
// `SecureTokenStorage`.

import 'dart:async';
import 'package:warehouse_os_app/features/auth/data/registration_repository.dart';

import 'package:warehouse_os_app/core/network/paginated_result.dart';
import 'package:warehouse_os_app/core/repositories/paged_query.dart';
import 'package:warehouse_os_app/features/admin/data/registration_queue_repository.dart';
import 'package:warehouse_os_app/core/error/failure.dart';
import 'package:warehouse_os_app/core/storage/secure_token_storage.dart';
import 'package:warehouse_os_app/features/auth/data/auth_models.dart';
import 'package:warehouse_os_app/features/auth/data/auth_repository.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_state.dart';

const testAccount = AuthAccount(id: 1, name: 'Test User', phone: '+9647701234567');
const testAdminAccount = AuthAccount(id: 2, name: 'Test Admin', phone: '+9647701234599');
const testBusiness = AuthBusiness(
  id: 1,
  name: 'Test Business',
  businessType: 'custom',
  logoUrl: null,
  currency: 'USD',
  language: 'en',
  timezone: 'UTC',
  status: 'active',
);

class InMemoryTokenStorage implements TokenStorage {
  String? _accessToken;
  String? _refreshToken;
  String? _accountType;

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> saveAccessToken(String accessToken) async => _accessToken = accessToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;
  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveAccountType(String accountType) async => _accountType = accountType;
  @override
  Future<String?> readAccountType() async => _accountType;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _accountType = null;
  }
}

/// Scriptable fake: tests set [loginResult]/[loginError] before pumping the
/// widget under test, then assert on what [AuthController] did with it.
class FakeAuthRepository implements AuthRepository {
  AuthSession? loginResult;
  Failure? loginError;
  int loginCallCount = 0;
  ({String phone, String password})? lastLoginArgs;

  /// When set, [login] waits on this instead of resolving immediately — lets
  /// a test hold the `AuthAuthenticating` state open across a `pump()` to
  /// assert on the loading UI before completing it with [pendingCompleter]'s
  /// own `.complete()`/`.completeError()`.
  Completer<void>? pendingCompleter;

  @override
  Future<AuthSession> login({required String phone, required String password}) async {
    loginCallCount += 1;
    lastLoginArgs = (phone: phone, password: password);
    if (pendingCompleter != null) await pendingCompleter!.future;
    if (loginError != null) throw loginError!;
    return loginResult ??
        const AuthSession(
          accessToken: 'fake-access-token',
          refreshToken: 'fake-refresh-token',
          account: testAccount,
          business: testBusiness,
        );
  }

  @override
  Future<RefreshedTokens> refresh(String refreshToken) async =>
      const RefreshedTokens(accessToken: 'fake-access-token-2', refreshToken: 'fake-refresh-token-2');

  bool logoutCalled = false;
  @override
  Future<void> logout(String? refreshToken) async => logoutCalled = true;

  @override
  Future<AuthIdentity> me() async => const AuthIdentity(account: testAccount, business: testBusiness);

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {}
}

/// For shell/routing tests that just need "some authenticated business
/// user" as a given, without exercising the login flow itself — skips
/// `AuthController`'s real `_restoreSession` (which would otherwise try a
/// real network call).
class FakeAuthenticatedController extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(account: testAccount, business: testBusiness);
}

class FakeUnauthenticatedController extends AuthController {
  @override
  AuthState build() => const AuthUnauthenticated();
}

/// `business: null` is the real signal (see `routing/app_router.dart`'s
/// `_redirect`) that lands a session in the System Admin shell rather than
/// the business one — same reasoning as [FakeAuthenticatedController], just
/// for admin-scoped router/navigation tests.
class FakeAdminAuthenticatedController extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(account: testAdminAccount, business: null);
}

// No typed helper functions here (Riverpod 3's override-list type isn't
// worth naming explicitly) — each test builds its own
// `ProviderScope(overrides: [...])` inline using the fakes above, e.g.:
//   ProviderScope(
//     overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)],
//     child: const WarehouseOsApp(),
//   )

/// Records the submitted application so a test can assert the wire format,
/// and can be made to fail on demand. Deliberately in the fakes file rather
/// than inside the test group — it implements a production interface, and
/// keeping it here means a change to that interface breaks compilation in
/// one obvious place.
class RecordingRegistrationRepository implements RegistrationRepository {
  RecordingRegistrationRepository({required this.onRegister, this.error});

  final void Function(RegistrationDraft draft) onRegister;
  final Failure? error;

  @override
  Future<RegistrationResult> register(RegistrationDraft draft) async {
    onRegister(draft);
    if (error != null) throw error!;
    return const RegistrationResult(
      status: 'pending',
      message: 'Your registration has been received and is awaiting review.',
    );
  }
}

/// Scriptable registration queue: records decisions so a test can assert
/// what the screen actually sent, and can be made to fail like the backend's
/// 409 when another administrator has already decided.
class FakeRegistrationQueue implements RegistrationQueueRepository {
  List<BusinessRegistration> items = [
    BusinessRegistration(
      id: 'reg-1',
      name: 'Applicant One',
      businessType: 'warehouse',
      phone: '+9647700000101',
      status: 'pending',
      createdAt: DateTime(2026, 9, 20),
      ownerName: 'Owner One',
      ownerPhone: '+9647700000102',
    ),
  ];

  final List<String> approved = [];
  final List<(String, String)> rejected = [];
  Failure? failWith;

  @override
  Future<PaginatedResult<BusinessRegistration>> list(PagedQuery query, {String? status}) async {
    final filtered = items.where((b) => status == null || b.status == status).toList();
    return PaginatedResult(items: filtered, page: 1, pageSize: filtered.length, total: filtered.length);
  }

  @override
  Future<BusinessRegistration> approve(String id) async {
    if (failWith != null) throw failWith!;
    approved.add(id);
    items = items.where((b) => b.id != id).toList();
    return items.isEmpty ? _decided(id, 'active') : _decided(id, 'active');
  }

  @override
  Future<BusinessRegistration> reject(String id, String reason) async {
    if (failWith != null) throw failWith!;
    rejected.add((id, reason));
    items = items.where((b) => b.id != id).toList();
    return _decided(id, 'rejected');
  }

  final List<RegistrationDraft> created = [];

  @override
  Future<void> createBusiness(RegistrationDraft draft) async => created.add(draft);

  BusinessRegistration _decided(String id, String status) => BusinessRegistration(
    id: id,
    name: 'Applicant One',
    businessType: 'warehouse',
    phone: '+9647700000101',
    status: status,
    createdAt: DateTime(2026, 9, 20),
  );
}
