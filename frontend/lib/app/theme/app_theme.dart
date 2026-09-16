import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The one place ThemeData is built — light and dark, from the same seed
/// color, so the two never drift into visually unrelated palettes (the same
/// discipline the architecture's artifact enforces for the web design
/// system). No screen sets its own colors/fonts directly; everything reads
/// from `Theme.of(context)`.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _themeFrom(Brightness.light);
  static ThemeData dark() => _themeFrom(Brightness.dark);

  static ThemeData _themeFrom(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
