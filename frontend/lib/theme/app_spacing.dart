/// Spacing scale (architecture §27/§3). Every `SizedBox`, `EdgeInsets`, and
/// `gap` in the shared component library reads from here — no raw pixel
/// numbers scattered through widgets. Values are a standard 4px-based scale,
/// which divides evenly for the compact/medium/comfortable density this
/// business app needs at each breakpoint (§5's responsive requirement).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// The minimum side gutter at any width, including phone — matches the
  /// same rule applied to the web architecture artifact.
  static const double pageGutter = 16;
}
