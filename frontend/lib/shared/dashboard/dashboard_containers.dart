import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'dashboard_cards.dart';

/// Reserves the space and chrome for a future chart (§5/§16's visual
/// reports — daily/weekly/monthly sales, stock movement, etc.). No
/// charting library is wired in yet (avoiding a dependency Phase 1 doesn't
/// need); a future phase drops a real chart widget where the placeholder
/// icon is.
class ChartContainer extends StatelessWidget {
  const ChartContainer({super.key, required this.title, this.height = 220});

  final String title;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SectionCard(
      title: title,
      child: SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_outlined, size: 36, color: colors.textMuted),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Chart will render here once connected to real data',
                style: TextStyle(color: colors.textMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps any dashboard widget with the enable/reorder affordance the
/// specification's dashboard-customization requirement needs (§49) — the
/// actual enable/disable/reorder *logic* (persisted per-business settings)
/// is a later phase; this only establishes that every dashboard widget is
/// individually wrappable, so retrofitting that logic later doesn't require
/// restructuring the dashboard's widget tree.
class DashboardWidgetContainer extends StatelessWidget {
  const DashboardWidgetContainer({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return visible ? child : const SizedBox.shrink();
  }
}
