import '../../data/auth_models.dart';

/// The states listed in the Phase 2 brief (§18), as a sealed class rather
/// than a generic `AsyncValue` — this state machine has more shapes than
/// "loading/data/error" (in particular, a distinct `AuthSessionExpired`
/// the UI treats differently from a fresh login error: it shows "your
/// session expired, please sign in again" rather than a form-validation-
/// style error under the password field).
sealed class AuthState {
  const AuthState();
}

/// Before the app has checked whether a stored session exists yet.
class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.account, required this.business});
  final AuthAccount account;
  final AuthBusiness? business;
}

/// A login/change-password attempt failed — the UI shows `message` inline
/// (e.g. under the password field) rather than navigating anywhere.
class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

/// A previously-authenticated session's refresh token was rejected (logout
/// elsewhere, revocation, real expiry) — distinct from `AuthError` so the
/// UI can show "Your session expired — please sign in again" instead of a
/// form error, and so the router redirect (routing/app_router.dart) can
/// treat it the same as `AuthUnauthenticated` for navigation purposes.
class AuthSessionExpired extends AuthState {
  const AuthSessionExpired();
}
