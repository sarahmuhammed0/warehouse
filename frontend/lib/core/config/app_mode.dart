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
