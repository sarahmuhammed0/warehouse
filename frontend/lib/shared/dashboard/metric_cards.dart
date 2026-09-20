import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';

/// A single number + label (§16/§5's dashboard stat tiles — total products,
/// low stock, today's sales, etc.). `value` is a plain string the caller
/// formats (currency/locale-aware formatting is a future-module concern,
/// not this widget's) — deliberately takes no real data source in Phase 1;
/// see `DashboardPlaceholderScreen` for how it's used with structural
/// placeholders instead of fabricated statistics.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.tone, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;

  /// When set, the entire card is tappable — e.g. the System Admin
  /// dashboard's cards drilling into the list they summarize.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tone ?? colors.primary;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: AppTypography.pageTitle.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
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
/// this widget just colors it green/red per `deltaPositive`.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
              if (deltaLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    deltaLabel!,
                    style: AppTypography.caption.copyWith(color: deltaColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
