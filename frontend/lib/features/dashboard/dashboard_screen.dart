import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/dashboard_containers.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/layout/responsive/responsive_layout.dart';
import '../../theme/app_spacing.dart';

/// Demonstrates the dashboard widget foundation (§16) arranged the way the
/// real dashboard eventually will be — stat tiles, a chart placeholder,
/// recent activity, and alerts — WITHOUT fabricated statistics (§16's
/// explicit rule). Every value below is a structural "—" placeholder, never
/// a plausible-looking fake number; this is UI-foundation only, not a
/// preview of real business data.
class DashboardPlaceholderScreen extends StatelessWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PageScaffold(
      title: l10n.navDashboard,
      subtitle: 'Statistics connect to real data once the business modules are built (Phase 2+).',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: const [
                StatCard(label: 'Total products', value: '—', icon: Icons.inventory_2_outlined),
                StatCard(label: "Today's sales", value: '—', icon: Icons.point_of_sale_outlined),
                StatCard(label: 'Low stock', value: '—', icon: Icons.warning_amber_outlined),
                StatCard(label: 'Pending orders', value: '—', icon: Icons.receipt_long_outlined),
              ],
            ),
            desktop: (context) => Row(
              children: const [
                Expanded(child: StatCard(label: 'Total products', value: '—', icon: Icons.inventory_2_outlined)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: "Today's sales", value: '—', icon: Icons.point_of_sale_outlined)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: 'Low stock', value: '—', icon: Icons.warning_amber_outlined)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: 'Pending orders', value: '—', icon: Icons.receipt_long_outlined)),
              ],
            ),
          ),
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                ChartContainer(title: l10n.dashboardKeyMetrics),
                ActivityListCard(title: l10n.dashboardRecentActivity, entries: const [], emptyLabel: l10n.dashboardNoActivityYet),
                AlertCard(title: l10n.dashboardAlerts, alerts: const [], emptyLabel: l10n.dashboardNoAlerts),
              ],
            ),
            desktop: (context) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: ChartContainer(title: l10n.dashboardKeyMetrics)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    spacing: AppSpacing.md,
                    children: [
                      ActivityListCard(title: l10n.dashboardRecentActivity, entries: const [], emptyLabel: l10n.dashboardNoActivityYet),
                      AlertCard(title: l10n.dashboardAlerts, alerts: const [], emptyLabel: l10n.dashboardNoAlerts),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
