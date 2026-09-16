import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// The one place `ThemeData` is built — light and dark, from the same
/// [AppColors] token sets, so the two never drift apart visually. No
/// screen or shared widget sets a raw color/font directly; everything
/// reads from `Theme.of(context)` (standard widgets) or `context.colors`
/// (the extra semantic tokens — §4's requirement that Settings can later
/// offer a theme switch without any widget needing to change).
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      surface: colors.surface,
      error: colors.error,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [colors],
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: AppTypography.textTheme(colors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: BorderSide(color: colors.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colors.error),
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: AppTypography.formLabel.copyWith(color: colors.textSecondary),
        hintStyle: AppTypography.body.copyWith(color: colors.textMuted),
        helperStyle: AppTypography.helperText.copyWith(color: colors.textMuted),
        errorStyle: AppTypography.helperText.copyWith(color: colors.error),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: AppRadius.smRadius,
        ),
        textStyle: AppTypography.caption.copyWith(
          color: brightness == Brightness.dark ? colors.background : colors.surface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.textPrimary,
        contentTextStyle: AppTypography.body.copyWith(
          color: brightness == Brightness.dark ? colors.background : colors.surface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
