import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Interface, not just a concrete class — so tests can substitute an
/// in-memory fake instead of hitting `flutter_secure_storage`'s platform
/// channel (unavailable in `flutter_test`'s pure-Dart environment). See
/// `test/features/auth/fakes.dart`.
abstract class TokenStorage {
  Future<void> save({required String accessToken, required String refreshToken});
  Future<void> saveAccessToken(String accessToken);
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();

  /// Which of the backend's two identity systems this stored session belongs
  /// to. Persisted because refresh and logout live on different routes per
  /// account type (`/api/auth/*` vs `/api/admin/auth/*`) — without it, a page
  /// reload would restore a System Admin's session by asking the
  /// business-user route to refresh a token it has never seen, and silently
  /// log them out.
  ///
  /// Stored as a plain string rather than the `AccountType` enum so this
  /// core-layer interface does not depend on a feature's model.
  Future<void> saveAccountType(String accountType);
  Future<String?> readAccountType();

  Future<void> clear();
}

/// Where the access/refresh tokens live on disk (Phase 2 §20). NOT
/// `shared_preferences`/plain `localStorage` — those are unencrypted,
/// readable by anything else with filesystem/JS access to the app's
/// storage. This wraps `flutter_secure_storage`, whose actual security
/// guarantee is genuinely different per platform — documented here rather
/// than assumed uniform:
///
///  - **Android**: backed by the Android Keystore (`EncryptedSharedPreferences`)
///    — hardware-backed on most devices. Strong guarantee.
///  - **iOS/macOS**: backed by Keychain. Strong guarantee.
///  - **Windows**: backed by the Windows Credential Manager (DPAPI-encrypted,
///    tied to the OS user account). Strong guarantee, OS-account-scoped.
///  - **Web**: ⚠️ genuinely weaker. There is no browser keychain API
///    equivalent — `flutter_secure_storage`'s web implementation stores
///    data in `window.localStorage`, encrypted with a key derived via the
///    WebCrypto API. This protects against a casual glance at localStorage
///    or a non-JS-executing attacker, but **not** against a successful XSS
///    attack in the same origin (which can call the same WebCrypto APIs
///    this package uses) — unlike a real OS keychain, there is no
///    hardware/process isolation on the web. This is a real, inherent
///    platform limitation, not a bug in this app; it's why access tokens
///    are short-lived (15 minutes) regardless of platform — see
///    docs/authentication.md "Token architecture".
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'warehouse_os.access_token';
  static const _refreshTokenKey = 'warehouse_os.refresh_token';
  static const _accountTypeKey = 'warehouse_os.account_type';

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<void> saveAccessToken(String accessToken) => _storage.write(key: _accessTokenKey, value: accessToken);

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);
  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> saveAccountType(String accountType) => _storage.write(key: _accountTypeKey, value: accountType);
  @override
  Future<String?> readAccountType() => _storage.read(key: _accountTypeKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accountTypeKey);
  }
}
