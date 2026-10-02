import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// [AppModeConfig.mode], read through a provider so a test can override it.
///
/// Most of the app never needs this: a module's provider uses the constant to
/// *select a repository*, and a test overrides that repository instead. This
/// exists for the handful of controllers that must branch on the mode inside
/// their own logic — the stock engine's double-posting guard, the notification
/// centre, the variant list. `flutter test` always compiles as demo, so without
/// it the backend branch of each is unreachable by any test, and safety logic
/// that cannot be exercised is a liability.
///
/// It is deliberately NOT a way to change mode at runtime: it reads the
/// compile-time constant and nothing in the app writes to it. See
/// docs/frontend-demo-mode.md on why a real backend failure must never fall
/// back to local data.
final appModeProvider = Provider<AppMode>((ref) => AppModeConfig.mode);

// A `LOGIN_AS` compile-time flag briefly lived here to make the System Admin
// route reachable in backend mode. It was replaced by the login screen's own
// account-type selector (`selectedAccountTypeProvider`) — a hidden mode that
// can only be chosen by relaunching the app is not usable, and the person
// signing in is the only one who knows which account type they hold.
