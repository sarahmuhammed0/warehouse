/// Breakpoint scale for the responsive foundation (architecture §28).
/// Values chosen to match common device classes, not arbitrary round
/// numbers — a business user's "tablet" is realistically a landscape iPad
/// or a similarly-sized Android tablet.
class AppBreakpoints {
  AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;
  // >= tablet is treated as desktop/laptop.
}

enum ScreenSize { mobile, tablet, desktop }

ScreenSize screenSizeFor(double width) {
  if (width < AppBreakpoints.mobile) return ScreenSize.mobile;
  if (width < AppBreakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.desktop;
}
