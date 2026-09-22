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
///
/// The palette carries the FactoryOS visual identity: a near-white neutral
/// canvas, pure-white surfaces, one deep professional blue doing all the
/// accent work, and a pale blue used only to seat icons and mark the
/// selected state. Status colors are deliberately desaturated — a status
/// pill has to read as information on a dense table, not as a warning
/// light.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.card,
    required this.border,
    required this.borderStrong,
    required this.shadow,
    required this.accentSoft,
    required this.brandGradientStart,
    required this.brandGradientEnd,
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

  /// A panel nested *inside* a card — the grey well behind a sub-list, a
  /// table's header row, a hovered row. One step off `card`, never a
  /// second bordered card, which is what keeps dense screens from turning
  /// into a stack of boxes inside boxes.
  final Color surfaceMuted;

  final Color card;

  /// The hairline that separates content. Faint by design: the card
  /// language leans on elevation and whitespace, and a border that
  /// competes with the shadow makes every surface look outlined.
  final Color border;

  /// The one step up from [border], for a control that has to read as
  /// interactive on its own (an outlined button, a focused field).
  final Color borderStrong;

  /// Base tint for card/overlay shadows — alpha is applied by
  /// `AppElevation`, never baked in here, so one token serves every
  /// elevation level.
  final Color shadow;

  /// The pale blue an icon sits on, and the fill behind a selected nav
  /// item. Always paired with [primary] as its foreground.
  final Color accentSoft;

  /// The two ends of the signature brand panel — the deep blue block a
  /// dashboard's headline figure sits on.
  final Color brandGradientStart;
  final Color brandGradientEnd;

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
    primary: Color(0xFF1B4F7C),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF3E7CAE),
    onSecondary: Color(0xFFFFFFFF),
    background: Color(0xFFF1F4F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F8FB),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE6ECF2),
    borderStrong: Color(0xFFD3DDE7),
    shadow: Color(0xFF0E1C2B),
    accentSoft: Color(0xFFE9F1F9),
    brandGradientStart: Color(0xFF24628F),
    brandGradientEnd: Color(0xFF12385C),
    textPrimary: Color(0xFF0E1C2B),
    textSecondary: Color(0xFF4B5B6C),
    textMuted: Color(0xFF8A98A8),
    success: Color(0xFF1E7A4C),
    successBg: Color(0xFFE7F4ED),
    warning: Color(0xFFA96412),
    warningBg: Color(0xFFFBF0E2),
    error: Color(0xFFB24328),
    errorBg: Color(0xFFFBEAE5),
    info: Color(0xFF1B4F7C),
    infoBg: Color(0xFFE9F1F9),
    disabled: Color(0xFFB3BFCB),
    disabledBg: Color(0xFFEEF2F6),
    selected: Color(0xFF1B4F7C),
    selectedBg: Color(0xFFE9F1F9),
  );

  static const AppColors dark = AppColors(
    primary: Color(0xFF74AEDC),
    onPrimary: Color(0xFF08243A),
    secondary: Color(0xFF5FA0CE),
    onSecondary: Color(0xFF06202F),
    background: Color(0xFF0E141B),
    surface: Color(0xFF151D26),
    surfaceMuted: Color(0xFF212B36),
    card: Color(0xFF1A232D),
    border: Color(0xFF27313D),
    borderStrong: Color(0xFF36414E),
    shadow: Color(0xFF000000),
    accentSoft: Color(0x2874AEDC),
    brandGradientStart: Color(0xFF1E4C72),
    brandGradientEnd: Color(0xFF122F49),
    textPrimary: Color(0xFFE8EDF2),
    textSecondary: Color(0xFFA8B6C3),
    textMuted: Color(0xFF76848F),
    success: Color(0xFF7BC49B),
    successBg: Color(0x247BC49B),
    warning: Color(0xFFE3A465),
    warningBg: Color(0x24E3A465),
    error: Color(0xFFE39177),
    errorBg: Color(0x24E39177),
    info: Color(0xFF74AEDC),
    infoBg: Color(0x2474AEDC),
    disabled: Color(0xFF4A5560),
    disabledBg: Color(0xFF1A232D),
    selected: Color(0xFF74AEDC),
    selectedBg: Color(0x2874AEDC),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? card,
    Color? border,
    Color? borderStrong,
    Color? shadow,
    Color? accentSoft,
    Color? brandGradientStart,
    Color? brandGradientEnd,
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
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      card: card ?? this.card,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      shadow: shadow ?? this.shadow,
      accentSoft: accentSoft ?? this.accentSoft,
      brandGradientStart: brandGradientStart ?? this.brandGradientStart,
      brandGradientEnd: brandGradientEnd ?? this.brandGradientEnd,
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
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      brandGradientStart: Color.lerp(brandGradientStart, other.brandGradientStart, t)!,
      brandGradientEnd: Color.lerp(brandGradientEnd, other.brandGradientEnd, t)!,
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
