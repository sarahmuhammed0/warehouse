/// Centralized configuration (Phase 0 foundation) — mirrors the backend's
/// `config/env.js`: the one place that reads runtime configuration, so no
/// widget or service reaches for `String.fromEnvironment` directly.
///
/// Flutter has no `.env` file support out of the box (that's a Node/dotenv
/// idiom) — the equivalent is compile-time `--dart-define` values, passed at
/// build/run time and baked into the binary. Nothing secret belongs here:
/// a Flutter app ships to end-user devices, so anything in this file is
/// effectively public. (There are no secrets to configure yet in Phase 0 —
/// this exists so later phases have exactly one place to add them, matching
/// the "no hard-coded secrets" rule from the architecture blueprint.)
///
/// Usage:
///   flutter run --dart-define=API_BASE_URL=http://localhost:4000/api
/// If omitted, defaults to the local dev backend from docs/environment.md.
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000/api',
  );

  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
}
