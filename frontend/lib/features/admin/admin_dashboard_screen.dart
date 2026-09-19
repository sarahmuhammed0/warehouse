import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/layout/responsive/responsive_layout.dart';
import '../../theme/app_spacing.dart';
import 'data/admin_providers.dart';

/// System Admin dashboard (spec §2/§36) — cross-tenant aggregate stats.
/// Previously deferred (Phase 2 built no System Admin UI); now real,
/// wired to `LocalAdminRepository`'s demo businesses exactly like the
/// business dashboard is wired to `LocalProductRepository` etc.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final businesses = ref.watch(adminBusinessListControllerProvider);
    final activity = ref.watch(adminRecentActivityProvider);

    final all = businesses.items;
    final active = all.where((b) => b.status.name == 'active').length;
    final disabled = all.where((b) => b.status.name == 'disabled').length;
    final totalProducts = all.fold<int>(0, (sum, b) => sum + b.productCount);
    final totalOrders = all.fold<int>(0, (sum, b) => sum + b.orderCount);
    final totalUsers = all.fold<int>(0, (sum, b) => sum + b.userCount);
    final totalSales = all.fold<double>(0, (sum, b) => sum + b.salesTotal);

    return PageScaffold(
      title: l10n.adminNavDashboard,
      subtitle: l10n.demoDataNotice,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                StatCard(label: l10n.adminNavBusinesses, value: '${all.length}', icon: Icons.apartment_outlined),
                StatCard(label: l10n.statusActive, value: '$active', icon: Icons.check_circle_outline),
                StatCard(label: l10n.statusDisabled, value: '$disabled', icon: Icons.block_outlined),
                StatCard(label: l10n.fieldEmployee, value: '$totalUsers', icon: Icons.people_outline),
              ],
            ),
            desktop: (context) => Row(
              children: [
                Expanded(child: StatCard(label: l10n.adminNavBusinesses, value: '${all.length}', icon: Icons.apartment_outlined)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.statusActive, value: '$active', icon: Icons.check_circle_outline)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.statusDisabled, value: '$disabled', icon: Icons.block_outlined)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.fieldEmployee, value: '$totalUsers', icon: Icons.people_outline)),
              ],
            ),
          ),
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                StatCard(label: l10n.navProducts, value: '$totalProducts', icon: Icons.inventory_2_outlined),
                StatCard(label: l10n.navOrders, value: '$totalOrders', icon: Icons.receipt_long_outlined),
                StatCard(label: l10n.navSales, value: totalSales.toStringAsFixed(0), icon: Icons.point_of_sale_outlined),
              ],
            ),
            desktop: (context) => Row(
              children: [
                Expanded(child: StatCard(label: l10n.navProducts, value: '$totalProducts', icon: Icons.inventory_2_outlined)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.navOrders, value: '$totalOrders', icon: Icons.receipt_long_outlined)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.navSales, value: totalSales.toStringAsFixed(0), icon: Icons.point_of_sale_outlined)),
              ],
            ),
          ),
          ActivityListCard(
            title: l10n.dashboardRecentActivity,
            entries: [
              for (final entry in activity.asData?.value ?? const [])
                ActivityListEntry(title: '${entry.businessName}: ${entry.description}', timestamp: '', icon: Icons.circle),
            ],
            emptyLabel: l10n.dashboardNoActivityYet,
          ),
          SectionCard(
            title: l10n.adminNavBusinesses,
            actions: [TextButton(onPressed: () => context.go(AppRoutes.adminBusinesses), child: Text(l10n.view))],
            child: Column(
              children: [
                for (final b in all.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text(b.name),
                    subtitle: Text(b.businessType),
                    onTap: () => context.push(AppRoutes.adminBusinessDetail(b.id)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
