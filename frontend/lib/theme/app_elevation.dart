import 'package:flutter/material.dart';

/// Elevation/shadow tokens. Deliberately restrained: this app leans on a
/// hairline `context.colors.border` for separation (cards, tables) and
/// reserves real shadow for things that genuinely float above content —
/// dialogs, dropdown/select menus, the mobile bottom sheet — matching §2's
/// "reliable, not decorative" direction rather than stacking shadows on
/// every card.
class AppElevation {
  AppElevation._();

  static const double none = 0;
  static const double raised = 1; // popovers, menus
  static const double overlay = 4; // dialogs, bottom sheets, drawers

  static List<BoxShadow> shadowFor(double elevation, {required Brightness brightness}) {
    if (elevation <= 0) return const [];
    final opacity = brightness == Brightness.dark ? 0.4 : 0.10;
    final blur = 4 + elevation * 3;
    final offsetY = 1 + elevation * 0.75;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: blur,
        offset: Offset(0, offsetY),
      ),
    ];
  }
}
