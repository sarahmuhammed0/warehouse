import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_mode.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/providers.dart';
import '../../../../core/storage/secure_token_storage.dart';
import '../../data/auth_models.dart';
import '../../data/auth_repository.dart';
import '../../data/demo_auth_repository.dart';
import 'auth_state.dart';

/// The one seam `AppModeConfig` is consulted at for auth — a pure function,
/// not inlined in the provider, specifically so it's unit-testable without
/// needing a live `ProviderContainer` or a real `--dart-define` flip (see
/// test/widget_test.dart's "Demo/backend mode selection" group).
AuthRepository buildAuthRepository(AppMode mode, ApiClient client, AccountType accountType) {
  return switch (mode) {
    // `accountType` picks which of the backend's two identity systems to
    // talk to — business users and System Admins live in separate tables
    // behind separate routes, so there is no endpoint that accepts both.
    // See docs/authentication.md "Flutter scope".
    AppMode.backend => ApiAuthRepository(client, accountType: accountType),
    AppMode.demo => DemoAuthRepository(),
  };
}

/// Which identity system the next login (and the current session's refresh
/// and logout) talks to. A runtime choice because the login screen offers
/// it — §4's login screen belongs to a business, and the two account types
/// live in separate backend tables behind separate routes, so something has
/// to pick one and only the person signing in knows which they are.
///
/// Defaults to a business user: that is the overwhelmingly common case, and
/// a wrong default must fail safe by asking the ordinary route rather than
/// the privileged one.
///
/// Restored from storage on startup by `AuthController._restoreSession` —
/// see `TokenStorage.saveAccountType` for why a reload would otherwise log
/// a System Admin straight back out.
class SelectedAccountType extends Notifier<AccountType> {
  @override
  AccountType build() => AccountType.businessUser;

  void select(AccountType type) => state = type;
}

final selectedAccountTypeProvider =
    NotifierProvider<SelectedAccountType, AccountType>(SelectedAccountType.new);

/// Serializes [AccountType] for [TokenStorage], which is core-layer and must
/// not import a feature's models. Kept next to the enum's only two users so
/// the two halves cannot drift.
String accountTypeToStorage(AccountType type) =>
    type == AccountType.systemAdmin ? 'system_admin' : 'business_user';

AccountType accountTypeFromStorage(String? raw) =>
    raw == 'system_admin' ? AccountType.systemAdmin : AccountType.businessUser;

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return buildAuthRepository(
    AppModeConfig.mode,
    ref.watch(apiClientProvider),
    // Ignored in demo mode, where the demo repository recognises the admin
    // identity from the phone number it is given and switches by itself.
    ref.watch(selectedAccountTypeProvider),
  );
});

final secureTokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The auth state machine (architecture §18/§24). Kept separate from any
/// business-module state (§18: "do not create fake business state") — a
/// module that needs to know "is someone logged in, and as whom" reads
/// this provider; it never maintains its own copy of that answer.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Fire-and-forget: restores a stored session (if any) without blocking
    // the first frame. Starts in AuthInitial — the router (routing/
    // app_router.dart) treats that as "not yet known, don't redirect yet".
    Future.microtask(_restoreSession);
    return const AuthInitial();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStorage get _storage => ref.read(secureTokenStorageProvider);

  Future<void> _restoreSession() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) {
      state = const AuthUnauthenticated();
      return;
    }
    // Point the repository at the identity system this stored session
    // actually belongs to, BEFORE `_repo` is read below. Skipping this asks
    // the business-user route to refresh a System Admin's token, which
    // fails and silently logs them out on every reload.
    ref
        .read(selectedAccountTypeProvider.notifier)
        .select(accountTypeFromStorage(await _storage.readAccountType()));
    try {
      final tokens = await _repo.refresh(refreshToken);
      await _storage.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken);
      final identity = await _repo.me();
      state = AuthAuthenticated(account: identity.account, business: identity.business, role: identity.role);
    } catch (_) {
      await _storage.clear();
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login({required String phone, required String password}) async {
    state = const AuthAuthenticating();
    try {
      final session = await _repo.login(phone: phone, password: password);
      await _storage.save(accessToken: session.accessToken, refreshToken: session.refreshToken);
      // Remember which identity system this session came from, so a reload
      // refreshes it against the same one.
      await _storage.saveAccountType(accountTypeToStorage(ref.read(selectedAccountTypeProvider)));
      state = AuthAuthenticated(account: session.account, business: session.business, role: session.role);
    } on Failure catch (e) {
      state = AuthError(e.message);
    } catch (_) {
      state = AuthError('Something went wrong. Please try again.');
    }
  }

  /// Lets the login screen return to a plain unauthenticated form after
  /// showing an error (e.g. once the user starts editing a field again) —
  /// without this, the error message would stay on screen forever.
  void clearError() {
    if (state is AuthError) state = const AuthUnauthenticated();
  }

  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    try {
      await _repo.logout(refreshToken);
    } catch (_) {
      // Best-effort: still clear the local session even if the network
      // call fails — the user asked to log out, and a stuck "logged in"
      // state because of a flaky connection would be worse than a
      // refresh token on the server outliving this client's copy of it
      // (it still expires on its own, and change-password/admin action
      // can revoke it).
    }
    await _storage.clear();
    state = const AuthUnauthenticated();
  }

  /// Called by the Dio auth interceptor (core/network/auth_interceptor.dart)
  /// when a refresh attempt itself fails — distinct from [logout] (user-
  /// initiated) so the UI can show "your session expired" instead of
  /// silently landing back on the login screen as if nothing happened.
  Future<void> handleSessionExpired() async {
    await _storage.clear();
    state = const AuthSessionExpired();
  }

  /// Returns true on success. On failure, leaves `state` untouched (the
  /// caller — a future Settings screen, not built this phase — shows the
  /// error itself) rather than routing through `AuthError`, since a failed
  /// password change should not look like a failed login.
  Future<bool> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      await _repo.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      // The backend revokes every session for this account on a password
      // change, including the one making this call (see
      // backend/src/modules/auth/authService.js) — signing in again with
      // the new password is required, by design, not a bug.
      await _storage.clear();
      state = const AuthUnauthenticated();
      return true;
    } on Failure {
      return false;
    }
  }
}
