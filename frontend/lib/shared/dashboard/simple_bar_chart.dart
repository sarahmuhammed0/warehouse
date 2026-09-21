import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A real bar chart over real numbers (spec §5's "visual reports").
///
/// Deliberately built from plain widgets rather than by adding a charting
/// package: Phase 1 recorded a decision not to take a chart dependency, and
/// the dashboard's series are small (7 days, 6 months, top 6 products), so
/// a `Column` of proportional bars renders them honestly with no new
/// third-party surface. It replaces a placeholder that read "Chart will
/// render here once connected to real data" — the data was always there.
///
/// Horizontal bars, not vertical: the labels are product and category names,
/// which do not fit under a vertical column at dashboard widths.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.points,
    required this.emptyLabel,
    this.valueFormatter,
  });

  /// `(label, value)` pairs, already ordered by the caller.
  final List<({String label, double value})> points;

  /// Shown when there is nothing to plot — an empty chart must say so
  /// rather than render an empty frame that looks broken.
  final String emptyLabel;

  final String Function(double)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final format = valueFormatter ?? (v) => v.toStringAsFixed(0);

    if (points.isEmpty || points.every((p) => p.value == 0)) {
      return SizedBox(
        height: 120,
        child: Center(child: Text(emptyLabel, style: AppTypography.caption.copyWith(color: colors.textMuted))),
      );
    }

    final max = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        for (final point in points)
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  point.label,
                  style: AppTypography.caption.copyWith(color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // `max` is non-zero here (the all-zero case returned
                    // above), so this division is safe.
                    final fraction = point.value / max;
                    return Stack(
                      children: [
                        Container(
                          height: 18,
                          decoration: BoxDecoration(color: colors.border.withValues(alpha: 0.35), borderRadius: AppRadius.smRadius),
                        ),
                        Container(
                          height: 18,
                          width: (constraints.maxWidth * fraction).clamp(2.0, constraints.maxWidth),
                          decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadius.smRadius),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 72,
                child: Text(
                  format(point.value),
                  textAlign: TextAlign.end,
                  style: AppTypography.caption.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
