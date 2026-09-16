import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, outline, text, destructive }

enum AppButtonSize { medium, small }

/// The one button every module uses (architecture §13). Variant is a
/// closed enum, not a free-form style override, specifically so a future
/// screen can't invent a seventh ad-hoc button look — consistency across
/// dozens of business screens is the point.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;

  /// Fills the available width — the common mobile pattern for a primary
  /// form action (§5's "forms should become mobile-friendly").
  final bool expand;

  bool get _disabled => onPressed == null || loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = size == AppButtonSize.small ? 34.0 : 42.0;
    final horizontalPadding = size == AppButtonSize.small ? AppSpacing.md : AppSpacing.lg;

    final (background, foreground, border) = switch (variant) {
      AppButtonVariant.primary => (colors.primary, colors.onPrimary, null),
      AppButtonVariant.secondary => (colors.selectedBg, colors.primary, null),
      AppButtonVariant.outline => (Colors.transparent, colors.textPrimary, colors.border),
      AppButtonVariant.text => (Colors.transparent, colors.primary, null),
      AppButtonVariant.destructive => (colors.errorBg, colors.error, null),
    };

    final content = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(label, style: AppTypography.button.copyWith(color: foreground)),
            ],
          );

    final button = SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Material(
        color: _disabled ? colors.disabledBg : background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: border != null ? BorderSide(color: _disabled ? colors.disabledBg : border) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: AppRadius.mdRadius,
          onTap: _disabled ? null : onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              child: _disabled && !loading
                  ? DefaultTextStyle.merge(
                      style: TextStyle(color: colors.disabled),
                      child: IconTheme.merge(data: IconThemeData(color: colors.disabled), child: content),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );

    return button;
  }
}

/// Icon-only action — table row actions, topbar icons. Same disabled/hover
/// semantics as [AppButton] without a label.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final button = IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      color: color ?? colors.textSecondary,
      disabledColor: colors.disabled,
      splashRadius: 20,
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
