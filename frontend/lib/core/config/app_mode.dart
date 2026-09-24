/// Frontend-only test mode (explicit instruction, separate from Phase 2's
/// real backend integration) — the ONE place the demo-vs-backend decision
/// is made. Nothing else in the app branches on "are we in demo mode";
/// everything downstream (auth repository selection, route guards) reads
/// through `authRepositoryProvider`/`AuthState`, which this file feeds.
///
/// Compile-time only, matching `core/config/env.dart`'s existing style —
/// not a runtime toggle, and deliberately not stored anywhere a UI action
/// could flip it: a real backend connection failure must never silently
/// fall back to fake local data (see docs/frontend-demo-mode.md "Why not a
/// runtime toggle").
///
/// Usage:
///   flutter run                                   # DEMO (the default)
///   flutter run --dart-define=APP_MODE=backend     # real backend required
enum AppMode { demo, backend }

class AppModeConfig {
  AppModeConfig._();

  static const String _raw = String.fromEnvironment('APP_MODE', defaultValue: 'demo');

  static final AppMode mode = _raw.trim().toLowerCase() == 'backend' ? AppMode.backend : AppMode.demo;

  static bool get isDemo => mode == AppMode.demo;
  static bool get isBackend => mode == AppMode.backend;
}

// A `LOGIN_AS` compile-time flag briefly lived here to make the System Admin
// route reachable in backend mode. It was replaced by the login screen's own
// account-type selector (`selectedAccountTypeProvider`) — a hidden mode that
// can only be chosen by relaunching the app is not usable, and the person
// signing in is the only one who knows which account type they hold.
