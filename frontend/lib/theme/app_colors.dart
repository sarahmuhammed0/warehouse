import 'package:flutter/material.dart';

/// Semantic color tokens (architecture §27/§3 of the design system spec).
/// Implemented as a [ThemeExtension] rather than static constants — Phase
/// 0's `AppColors` was three static consts, which doesn't scale to a full
/// semantic palette with light/dark variants and doesn't participate in
/// Flutter's theme-animation/inheritance system. A `ThemeExtension` does:
/// it's reactive to theme changes, themeable per-widget in tests, and is
/// how Flutter itself recommends adding tokens beyond `ColorScheme`.
///
/// No widget should ever write a raw `Color(0x...)` for something this
/// class already names — read `context.colors.<token>` instead.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.info,
    required this.infoBg,
    required this.disabled,
    required this.disabledBg,
    required this.selected,
    required this.selectedBg,
  });

  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color surface;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color info;
  final Color infoBg;
  final Color disabled;
  final Color disabledBg;
  final Color selected;
  final Color selectedBg;

  static const AppColors light = AppColors(
    primary: Color(0xFF1C5F8F),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF2C7A7B),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF3F6F7),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFD8DFE3),
    textPrimary: Color(0xFF161D27),
    textSecondary: Color(0xFF4B5866),
    textMuted: Color(0xFF7C8894),
    success: Color(0xFF276B48),
    successBg: Color(0xFFE2F0E7),
    warning: Color(0xFFA85A17),
    warningBg: Color(0xFFF6E9DC),
    error: Color(0xFFA8431C),
    errorBg: Color(0xFFF7E8DE),
    info: Color(0xFF1C5F8F),
    infoBg: Color(0xFFE5EEF4),
    disabled: Color(0xFFB5BEC6),
    disabledBg: Color(0xFFEDF0F2),
    selected: Color(0xFF1C5F8F),
    selectedBg: Color(0xFFE5EEF4),
  );

  static const AppColors dark = AppColors(
    primary: Color(0xFF7FB8E0),
    onPrimary: Color(0xFF0B2536),
    secondary: Color(0xFF4FB3B0),
    onSecondary: Color(0xFF06201F),
    background: Color(0xFF10151B),
    surface: Color(0xFF171E26),
    card: Color(0xFF1C242B),
    border: Color(0xFF2A333D),
    textPrimary: Color(0xFFE7EBEE),
    textSecondary: Color(0xFFA9B6C0),
    textMuted: Color(0xFF77838E),
    success: Color(0xFF7FC79F),
    successBg: Color(0x247FC79F),
    warning: Color(0xFFE7A768),
    warningBg: Color(0x24E7A768),
    error: Color(0xFFE79A72),
    errorBg: Color(0x24E79A72),
    info: Color(0xFF7FB8E0),
    infoBg: Color(0x247FB8E0),
    disabled: Color(0xFF4B5560),
    disabledBg: Color(0xFF1C242B),
    selected: Color(0xFF7FB8E0),
    selectedBg: Color(0x247FB8E0),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? background,
    Color? surface,
    Color? card,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? error,
    Color? errorBg,
    Color? info,
    Color? infoBg,
    Color? disabled,
    Color? disabledBg,
    Color? selected,
    Color? selectedBg,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      disabled: disabled ?? this.disabled,
      disabledBg: disabledBg ?? this.disabledBg,
      selected: selected ?? this.selected,
      selectedBg: selectedBg ?? this.selectedBg,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledBg: Color.lerp(disabledBg, other.disabledBg, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      selectedBg: Color.lerp(selectedBg, other.selectedBg, t)!,
    );
  }
}

/// `context.colors.textMuted` instead of `Theme.of(context).extension<AppColors>()!.textMuted`
/// everywhere — every shared widget uses this.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
