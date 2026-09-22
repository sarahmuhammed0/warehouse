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
///
/// Buttons are pills in this design language. [AppButtonVariant.outline] is
/// a *white* pill with a hairline rather than a transparent one, because
/// the surfaces it sits on are themselves white or near-white and a
/// transparent outline button on a white card has no edge to speak of.
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
    final small = size == AppButtonSize.small;
    final height = small ? 36.0 : 44.0;
    final horizontalPadding = small ? AppSpacing.lg : AppSpacing.xl;

    final (background, foreground, border) = switch (variant) {
      AppButtonVariant.primary => (colors.primary, colors.onPrimary, null),
      AppButtonVariant.secondary => (colors.accentSoft, colors.primary, null),
      AppButtonVariant.outline => (colors.surface, colors.textPrimary, colors.borderStrong),
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
                Icon(icon, size: small ? 16 : 17, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              // Flexible + ellipsis, not a bare Text: `mainAxisSize.min`
              // otherwise insists on the label's full intrinsic width, so a
              // long label inside a narrow parent (e.g. a 380px-capped
              // login card) overflows instead of shrinking — a real
              // rendering bug, same class as AppDropdownField's earlier
              // missing `isExpanded`.
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.button.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Material(
        color: _disabled ? colors.disabledBg : background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.pillRadius,
          side: border != null
              ? BorderSide(color: _disabled ? colors.disabledBg : border)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _disabled ? null : onPressed,
          hoverColor: foreground.withValues(alpha: 0.07),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              // `widthFactor: 1` unless the button is deliberately
              // expanding. A bare `Center` fills whatever width it is
              // offered, which is invisible inside a `Row` (children get
              // unbounded main-axis constraints there) but turns every
              // button inside a `Wrap` into a full-width bar — the Wrap
              // hands its children the full line width. That is what the
              // dashboard's quick actions and the System Admin's §57
              // Controls row were doing.
              widthFactor: expand ? null : 1.0,
              child: _disabled && !loading
                  ? DefaultTextStyle.merge(
                      style: TextStyle(color: colors.disabled),
                      child: IconTheme.merge(
                        data: IconThemeData(color: colors.disabled),
                        child: content,
                      ),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
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
      icon: Icon(icon, size: 19),
      onPressed: onPressed,
      color: color ?? colors.textSecondary,
      disabledColor: colors.disabled,
      style: IconButton.styleFrom(
        hoverColor: colors.surfaceMuted,
        shape: const CircleBorder(),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A segmented pill toggle — the `Weekly | Monthly` control in the
/// reference. One row, one selected segment filled with the brand accent,
/// the whole thing seated on a muted track.
///
/// Used wherever a small, closed set of views share one panel. It is not a
/// replacement for tabs across a *page*; it switches the contents of a
/// single card.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label, Key? key})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _Segment(
              key: segment.key,
              label: segment.label,
              selected: segment.value == selected,
              onTap: () => onChanged(segment.value),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: AppRadius.pillRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Text(
            label,
            style: AppTypography.button.copyWith(
              color: selected ? colors.onPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
