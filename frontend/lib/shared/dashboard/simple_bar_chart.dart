import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A real bar chart over real numbers (spec §5's "visual reports").
///
/// Deliberately built from plain widgets rather than by adding a charting
/// package: the dashboard's series are small (7 days, 6 months, top 6
/// products), so a `Column` of proportional bars renders them honestly with
/// no new third-party surface.
///
/// Horizontal bars, not vertical: the labels are product and category
/// names, which do not fit under a vertical column at dashboard widths.
/// The reference design's chart is vertical, but it plots six short month
/// abbreviations — a different problem. What is adopted from it instead is
/// the *treatment*: fully rounded capsule bars on a pale track, no
/// gridlines, muted labels, and a single bar picked out in full strength.
///
/// That highlighted bar is the series maximum, not decoration — it answers
/// "which was the biggest?" without the reader having to scan the value
/// column, which is the same question the reference's dark bar answers.
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
        height: 140,
        child: Center(
          child: Text(emptyLabel, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ),
      );
    }

    final max = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        for (final point in points)
          Row(
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  point.label,
                  style: AppTypography.caption.copyWith(color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // `max` is non-zero here (the all-zero case returned
                    // above), so this division is safe.
                    final fraction = point.value / max;
                    final isPeak = point.value == max;
                    return Stack(
                      children: [
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: colors.surfaceMuted,
                            borderRadius: AppRadius.pillRadius,
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          height: 20,
                          width: (constraints.maxWidth * fraction).clamp(4.0, constraints.maxWidth),
                          decoration: BoxDecoration(
                            color: isPeak ? colors.primary : colors.primary.withValues(alpha: 0.28),
                            borderRadius: AppRadius.pillRadius,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 78,
                child: Text(
                  format(point.value),
                  textAlign: TextAlign.end,
                  style: AppTypography.caption.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
