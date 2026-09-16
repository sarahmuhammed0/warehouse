import 'package:flutter/widgets.dart';

import 'app_breakpoints.dart';

/// The one responsive-switching primitive every later screen builds on
/// (architecture §28: sidebar collapses to a drawer on tablet/mobile,
/// tables become card lists on mobile, etc.). Phase 0 ships the mechanism
/// only — no business screen uses it yet, but `SystemStatusPage`'s layout
/// is already built on top of it so the pattern is proven end to end.
///
/// Any of the three builders may be omitted; layout falls back to the next
/// larger one that's defined (mobile → tablet → desktop).
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key, this.mobile, this.tablet, required this.desktop});

  final WidgetBuilder? mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = screenSizeFor(width);

    switch (size) {
      case ScreenSize.mobile:
        return (mobile ?? tablet ?? desktop)(context);
      case ScreenSize.tablet:
        return (tablet ?? desktop)(context);
      case ScreenSize.desktop:
        return desktop(context);
    }
  }
}

/// Convenience for the common case of "just tell me which size I'm in"
/// inside a widget that otherwise doesn't need three separate builders.
extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize => screenSizeFor(MediaQuery.sizeOf(this).width);
  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;
}
