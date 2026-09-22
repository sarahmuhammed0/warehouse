import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_elevation.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The one place `ThemeData` is built — light and dark, from the same
/// [AppColors] token sets, so the two never drift apart visually. No
/// screen or shared widget sets a raw color/font directly; everything
/// reads from `Theme.of(context)` (standard widgets) or `context.colors`
/// (the extra semantic tokens — §4's requirement that Settings can later
/// offer a theme switch without any widget needing to change).
///
/// Everything Material draws on its own — a `PopupMenuButton`'s menu, a
/// `DropdownButton`'s overlay, a `Checkbox`, a `SnackBar` — is themed here
/// rather than at its call sites. That is what keeps a control the app
/// never wrote a wrapper for from showing up with Material's stock look in
/// the middle of a FactoryOS screen.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      error: colors.error,
    );

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [colors],
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.border,
      // `InkSparkle` scatters a bright burst across the tap target. On the
      // calm, low-contrast surfaces this design uses it reads as a flash
      // rather than as feedback, so ripples stay on Material's plain
      // splash — §28's "subtle animations only".
      splashFactory: InkRipple.splashFactory,
      textTheme: AppTypography.textTheme(colors.textPrimary),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 20),

      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
      ),

      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),

      dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),

      inputDecorationTheme: InputDecorationTheme(
        border: fieldBorder(colors.border),
        enabledBorder: fieldBorder(colors.border),
        focusedBorder: fieldBorder(colors.primary, 1.5),
        errorBorder: fieldBorder(colors.error),
        focusedErrorBorder: fieldBorder(colors.error, 1.5),
        disabledBorder: fieldBorder(colors.disabledBg),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        labelStyle: AppTypography.formLabel.copyWith(color: colors.textSecondary),
        floatingLabelStyle: AppTypography.formLabel.copyWith(color: colors.primary),
        hintStyle: AppTypography.body.copyWith(color: colors.textMuted),
        helperStyle: AppTypography.helperText.copyWith(color: colors.textMuted),
        errorStyle: AppTypography.helperText.copyWith(color: colors.error),
        prefixIconColor: colors.textMuted,
        suffixIconColor: colors.textMuted,
      ),

      // Every dropdown/overflow menu in the app — including the ones
      // Flutter builds itself inside `DropdownButton` and
      // `PopupMenuButton`.
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: colors.shadow.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: BorderSide(color: colors.border),
        ),
        textStyle: AppTypography.body.copyWith(color: colors.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.mdRadius,
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.mdRadius,
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
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
        elevation: AppElevation.overlay,
        shadowColor: colors.shadow.withValues(alpha: 0.2),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
        contentTextStyle: AppTypography.body.copyWith(color: colors.textSecondary),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(AppRadius.xl)),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceMuted,
        selectedColor: colors.accentSoft,
        side: BorderSide(color: colors.border),
        labelStyle: AppTypography.label.copyWith(color: colors.textSecondary),
        secondaryLabelStyle: AppTypography.label.copyWith(color: colors.primary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        showCheckmark: false,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        side: BorderSide(color: colors.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.primary : colors.borderStrong,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.onPrimary : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.primary : colors.disabledBg,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : colors.borderStrong,
        ),
      ),

      // Inventory and Reports each use a real `TabBar`. Themed here so
      // they read as the same control family as the rest of the app —
      // quiet labels, one accent underline, and none of Material's default
      // full-width divider cutting across the card.
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: AppTypography.button,
        unselectedLabelStyle: AppTypography.button.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: colors.primary,
        indicator: UnderlineTabIndicator(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          borderSide: BorderSide(color: colors.primary, width: 2.5),
        ),
        dividerColor: colors.border,
        overlayColor: WidgetStatePropertyAll(colors.surfaceMuted),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(colors.borderStrong),
        radius: const Radius.circular(AppRadius.xs),
        thickness: const WidgetStatePropertyAll(8),
      ),

      // The shell renders its own chrome; these keep any stock Material
      // text/icon button that slips through on-palette rather than
      // falling back to the seed color.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: AppTypography.button,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colors.textSecondary),
      ),

      visualDensity: VisualDensity.standard,
    );
  }
}
