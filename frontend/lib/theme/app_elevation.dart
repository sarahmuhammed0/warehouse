import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Elevation/shadow tokens.
///
/// The FactoryOS card language separates surfaces with a soft, wide, very
/// low-opacity shadow rather than with a drawn border — a white card on a
/// near-white canvas needs *something*, and a hairline outline on every
/// panel makes a dense screen look like a wireframe. The shadows here are
/// deliberately large-blur/low-alpha: visible as a lift, never as a drop
/// shadow you can point at.
///
/// Dark mode uses the same shapes at higher alpha, since a shadow has to
/// work much harder to separate two dark surfaces.
class AppElevation {
  AppElevation._();

  static const double none = 0;

  /// Everyday content surfaces — cards, tables, the shell's bars.
  static const double card = 1;

  /// Popovers, dropdown menus, the sticky shell chrome.
  static const double raised = 2;

  /// Dialogs, bottom sheets, drawers.
  static const double overlay = 4;

  /// The soft lift under a content card. Two stacked shadows: a tight one
  /// that defines the edge, and a wide diffuse one that does the actual
  /// lifting.
  static List<BoxShadow> cardShadow(AppColors colors, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: colors.shadow.withValues(alpha: dark ? 0.30 : 0.028),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: dark ? 0.24 : 0.045),
        blurRadius: 18,
        spreadRadius: -4,
        offset: const Offset(0, 6),
      ),
    ];
  }

  /// A stronger lift for things that genuinely float over content.
  static List<BoxShadow> overlayShadow(AppColors colors, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: colors.shadow.withValues(alpha: dark ? 0.45 : 0.10),
        blurRadius: 32,
        spreadRadius: -6,
        offset: const Offset(0, 14),
      ),
    ];
  }

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

/// `context.cardShadow` / `context.overlayShadow` — the two shadows a
/// widget actually reaches for, without having to also look up the
/// brightness and the color set at every call site.
extension AppElevationContext on BuildContext {
  List<BoxShadow> get cardShadow =>
      AppElevation.cardShadow(colors, Theme.of(this).brightness);
  List<BoxShadow> get overlayShadow =>
      AppElevation.overlayShadow(colors, Theme.of(this).brightness);
}
