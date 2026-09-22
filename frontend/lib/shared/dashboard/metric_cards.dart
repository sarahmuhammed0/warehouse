import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';
import '../cards/app_icon_chip.dart';
import '../cards/brand_panel.dart';

/// A single number + label (§16/§5's dashboard stat tiles — total products,
/// low stock, today's sales, etc.). `value` is a plain string the caller
/// formats.
///
/// The hierarchy is the point: the figure is the loudest thing on the card
/// and the label is a quiet caption beneath it, with the icon seated in a
/// pale chip rather than floated on the surface. That is what lets a row of
/// six of these read as six numbers instead of six captions (§11).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.onTap,
    this.delta,
    this.deltaPositive,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;

  /// When set, the entire card is tappable — e.g. the System Admin
  /// dashboard's cards drilling into the list they summarize. Left null
  /// the card is informational and is not dressed up as a button.
  final VoidCallback? onTap;

  /// An optional comparison line ("+18.4%"), colored by [deltaPositive].
  final String? delta;
  final bool? deltaPositive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final deltaColor = deltaPositive == null
        ? colors.textMuted
        : (deltaPositive! ? colors.success : colors.error);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIconChip(icon: icon!, tone: tone),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: SplitValueText(
                        value: value,
                        style: AppTypography.kpiValue,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (delta != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          delta!,
                          style: AppTypography.caption.copyWith(
                            color: deltaColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTypography.kpiLabel.copyWith(color: colors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A stat plus a comparison — e.g. against last period or a target (§16).
/// `deltaLabel` carries its own sign/wording (e.g. "+4.2% vs last month");
/// this widget just colors it green/red per `deltaPositive` and renders it
/// as a pill beside the figure, matching the reference's trend markers.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.deltaLabel,
    this.deltaPositive,
  });

  final String label;
  final String value;
  final String? deltaLabel;
  final bool? deltaPositive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final deltaColor = deltaPositive == null
        ? colors.textMuted
        : (deltaPositive! ? colors.success : colors.error);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.kpiLabel.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: SplitValueText(
                  value: value,
                  style: AppTypography.kpiValue,
                  color: colors.textPrimary,
                ),
              ),
              if (deltaLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: StatusPill(label: deltaLabel!, color: deltaColor),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact tinted pill for a number-adjacent annotation — a delta, a
/// count ("4 orders"), a short qualifier. Not a [StatusBadge]: that one
/// carries a *status* from the business catalog and is always uppercase;
/// this is plain supporting text that happens to be enclosed.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
