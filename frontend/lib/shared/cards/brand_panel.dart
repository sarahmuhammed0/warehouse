import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The deep-blue block a screen's single most important figure sits on —
/// the signature element of the FactoryOS dashboards (today's revenue on
/// the business side, the platform's account count on the admin side).
///
/// There is deliberately **one** of these per dashboard. Its entire job is
/// to break the run of white cards at exactly one point, so the eye lands
/// on the figure that matters before it starts reading. A second one on
/// the same screen would cancel the first out.
///
/// [eyebrow] is the small caps line above the label (the business name, the
/// platform name), [label] the quiet description, [value] the figure, and
/// [footnote]/[trailing] the small supporting row along the bottom.
class BrandPanel extends StatelessWidget {
  const BrandPanel({
    super.key,
    required this.eyebrow,
    required this.label,
    required this.value,
    this.footnote,
    this.trailing,
    this.icon,
    this.stats = const [],
    this.wide = false,
    this.onTap,
  });

  final String eyebrow;
  final String label;
  final String value;
  final String? footnote;

  /// The right-hand end of the footer row — a date, a count, a status.
  final String? trailing;

  /// Watermark glyph at the top-right, at low opacity.
  final IconData? icon;

  /// Supporting figures shown beside the headline once the panel is wide
  /// enough to hold them, and folded into the footer line when it isn't.
  /// They exist so a full-width hero band carries real content instead of
  /// becoming a mostly-empty slab of colour.
  final List<({String label, String value})> stats;

  /// Lays the supporting figures out beside the headline instead of under
  /// it. A caller-supplied flag rather than something this widget measures
  /// for itself: measuring means a `LayoutBuilder`, which builds during
  /// layout, and the panel is nested inside cards and rows that are
  /// themselves laid out — the caller always already knows whether it
  /// handed this panel a full-width band or a one-third column.
  final bool wide;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // White-on-blue regardless of theme: the panel supplies its own dark
    // ground in both light and dark mode, so it must not read foreground
    // colors from the surrounding surface.
    const onBrand = Color(0xFFFFFFFF);
    final onBrandMuted = onBrand.withValues(alpha: 0.66);

    Widget headline() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    eyebrow.toUpperCase(),
                    style: AppTypography.overline.copyWith(color: onBrand),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(icon, size: 18, color: onBrand.withValues(alpha: 0.5)),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: onBrandMuted),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: AppTypography.kpiValueLarge.copyWith(color: onBrand)),
            ),
          ],
        );

    Widget statBlock(({String label, String value}) stat) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stat.value,
              style: AppTypography.cardTitle.copyWith(color: onBrand, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              stat.label,
              style: AppTypography.caption.copyWith(color: onBrandMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

    Widget footer() {
      if (footnote == null && trailing == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Row(
          children: [
            if (footnote != null)
              Expanded(
                child: Text(
                  footnote!,
                  style: AppTypography.caption.copyWith(color: onBrandMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            if (trailing != null)
              Text(trailing!, style: AppTypography.caption.copyWith(color: onBrandMuted)),
          ],
        ),
      );
    }

    final spread = wide && stats.isNotEmpty;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: spread
          // The footer spans the whole panel rather than riding under the
          // headline column — otherwise its right-aligned item (the date)
          // lands in the middle of the panel, under the stats' left edge,
          // looking dropped rather than placed.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: headline()),
                    for (final stat in stats) ...[
                      Container(
                        width: 1,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                        color: onBrand.withValues(alpha: 0.18),
                      ),
                      Flexible(child: statBlock(stat)),
                    ],
                  ],
                ),
                footer(),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                headline(),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.xxl,
                    runSpacing: AppSpacing.md,
                    children: [for (final stat in stats) statBlock(stat)],
                  ),
                ],
                footer(),
              ],
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [colors.brandGradientStart, colors.brandGradientEnd],
        ),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.lgRadius,
        child: Material(
          type: MaterialType.transparency,
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  hoverColor: const Color(0x14FFFFFF),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

/// A large figure rendered with its fractional part de-emphasised —
/// `$48,650` bold, `.90` lighter — so a money column reads at the
/// magnitude that matters without losing the cents.
///
/// Splits on the locale's own decimal separator rather than assuming ".",
/// because the same screen renders under Arabic and Kurdish too.
class SplitValueText extends StatelessWidget {
  const SplitValueText({
    super.key,
    required this.value,
    this.style,
    this.color,
    this.mutedColor,
    this.separator = '.',
  });

  final String value;
  final TextStyle? style;
  final Color? color;
  final Color? mutedColor;
  final String separator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = (style ?? AppTypography.kpiValue).copyWith(color: color ?? colors.textPrimary);
    final index = value.lastIndexOf(separator);

    if (index <= 0 || index == value.length - 1) {
      return Text(value, style: base, overflow: TextOverflow.ellipsis);
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: value.substring(0, index)),
          TextSpan(
            text: value.substring(index),
            style: base.copyWith(color: mutedColor ?? colors.textMuted),
          ),
        ],
      ),
    );
  }
}
