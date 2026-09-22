import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The dashboard's overview chart — tall rounded capsule columns on a plain
/// ground, with the peak column picked out in full brand strength and
/// carrying a callout bubble.
///
/// This is the reference design's chart, and it works here because the
/// series it plots are short and their labels are short: six months, seven
/// weekday abbreviations. It is deliberately *not* a replacement for
/// `SimpleBarChart`, which plots the ten report series — those are labelled
/// with product and category names, which have nowhere to go under a
/// vertical column.
///
/// Drawn from layout widgets rather than a canvas so the columns animate
/// and hit-test for free, and so no charting dependency is added.
class VerticalBarChart extends StatelessWidget {
  const VerticalBarChart({
    super.key,
    required this.points,
    required this.emptyLabel,
    this.height = 240,
    this.valueFormatter,
    this.selectedIndex,
    this.onSelected,
  });

  /// `(label, value)` pairs, already ordered by the caller.
  final List<({String label, double value})> points;

  final String emptyLabel;
  final double height;
  final String Function(double)? valueFormatter;

  /// Which column carries the callout. Defaults to the series peak, which
  /// is the question a glance at a bar chart is usually asking.
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final format = valueFormatter ?? (v) => v.toStringAsFixed(0);

    if (points.isEmpty || points.every((p) => p.value == 0)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(emptyLabel, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ),
      );
    }

    final max = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    var peak = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i].value == max) { peak = i; break; }
    }
    final highlighted = selectedIndex ?? peak;
    // Room for the callout bubble above the tallest column and the axis
    // label below every column. Derived from the height this widget was
    // given rather than measured with a `LayoutBuilder`: a LayoutBuilder
    // here cannot be laid out by anything that asks for intrinsic sizes
    // (an `IntrinsicHeight` row of cards, say), and it fails at runtime
    // rather than at compile time.
    const calloutHeight = 30.0;
    const labelHeight = 26.0;
    final plotHeight = (height - calloutHeight - labelHeight).clamp(0.0, double.infinity);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Value axis. Four labels, not a dense ruler — the columns carry
          // the comparison and the callout carries the exact figure.
          SizedBox(
            width: 46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 4; i >= 0; i--)
                  Padding(
                    // The last label sits on the baseline, where the
                    // column labels start, so it needs to clear them.
                    padding: EdgeInsets.only(bottom: i == 0 ? 26 : 0),
                    child: Text(
                      format(max * i / 4),
                      style: AppTypography.caption.copyWith(color: colors.textMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(bottom: 26, child: _GridLines(color: colors.border)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < points.length; i++)
                      Expanded(
                        child: _Column(
                          label: points[i].label,
                          fraction: max == 0 ? 0 : points[i].value / max,
                          plotHeight: plotHeight,
                          calloutHeight: calloutHeight,
                          labelHeight: labelHeight,
                          highlighted: i == highlighted,
                          valueLabel: format(points[i].value),
                          onTap: onSelected == null ? null : () => onSelected!(i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four horizontal rules behind the columns. Dashed and very faint: they
/// are there to let the eye carry a column's height across to the axis, not
/// to be read as content.
class _GridLines extends StatelessWidget {
  const _GridLines({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter(color: color), size: Size.infinite);
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const rows = 4;
    const dash = 4.0;
    const gap = 5.0;
    for (var r = 0; r <= rows; r++) {
      final y = size.height * r / rows;
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + dash).clamp(0, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}

class _Column extends StatelessWidget {
  const _Column({
    required this.label,
    required this.fraction,
    required this.plotHeight,
    required this.calloutHeight,
    required this.labelHeight,
    required this.highlighted,
    required this.valueLabel,
    required this.onTap,
  });

  final String label;
  final double fraction;
  final double plotHeight;
  final double calloutHeight;
  final double labelHeight;
  final bool highlighted;
  final String valueLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final barHeight = (plotHeight * fraction).clamp(3.0, plotHeight);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdRadius,
      hoverColor: colors.primary.withValues(alpha: 0.05),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: calloutHeight,
            child: highlighted
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: AppRadius.pillRadius,
                      ),
                      child: Text(
                        valueLabel,
                        style: AppTypography.caption.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                : null,
          ),
          // The column takes a little over half its slot, which leaves the
          // gap between columns that makes a bar chart readable. A
          // fraction rather than a measured width, for the same reason the
          // heights are not measured — see `VerticalBarChart.build`.
          FractionallySizedBox(
            widthFactor: 0.52,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: barHeight,
              decoration: BoxDecoration(
                color: highlighted ? colors.primary : colors.primary.withValues(alpha: 0.22),
                borderRadius: AppRadius.pillRadius,
              ),
            ),
          ),
          SizedBox(
            height: labelHeight,
            child: Center(
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: highlighted ? colors.textPrimary : colors.textMuted,
                  fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A filled sparkline — the small shape-of-the-trend graphic beside a
/// headline figure. No axes, no labels, no values: if a number needs those
/// it needs a real chart, and this is for the ones that only need "and it
/// has been going up".
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 72, this.color});

  final List<double> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color ?? colors.primary),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    // A flat series would divide by zero; draw it down the middle instead.
    final span = (max - min).abs() < 0.0001 ? 1.0 : max - min;

    Offset pointAt(int i) {
      final x = size.width * i / (values.length - 1);
      final normalized = (max - min).abs() < 0.0001 ? 0.5 : (values[i] - min) / span;
      // Inset top and bottom so the extremes are not clipped by the edge.
      final y = size.height - 4 - normalized * (size.height - 8);
      return Offset(x, y);
    }

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final prev = pointAt(i - 1);
      final next = pointAt(i);
      // Cubic through the midpoint: a smooth trend, without the overshoot
      // a spline through every point would invent between samples.
      final controlX = (prev.dx + next.dx) / 2;
      line.cubicTo(controlX, prev.dy, controlX, next.dy, next.dx, next.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
