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
import 'data/admin_business_models.dart';
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
                StatCard(label: l10n.adminNavBusinesses, value: '${all.length}', icon: Icons.apartment_outlined, onTap: () => _openBusinesses(context, ref)),
                StatCard(label: l10n.statusActive, value: '$active', icon: Icons.check_circle_outline, onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.active)),
                StatCard(label: l10n.statusDisabled, value: '$disabled', icon: Icons.block_outlined, onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.disabled)),
                StatCard(label: l10n.fieldEmployee, value: '$totalUsers', icon: Icons.people_outline, onTap: () => context.push(AppRoutes.employees)),
              ],
            ),
            desktop: (context) => Row(
              children: [
                Expanded(child: StatCard(label: l10n.adminNavBusinesses, value: '${all.length}', icon: Icons.apartment_outlined, onTap: () => _openBusinesses(context, ref))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.statusActive, value: '$active', icon: Icons.check_circle_outline, onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.active))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.statusDisabled, value: '$disabled', icon: Icons.block_outlined, onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.disabled))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.fieldEmployee, value: '$totalUsers', icon: Icons.people_outline, onTap: () => context.push(AppRoutes.employees))),
              ],
            ),
          ),
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                StatCard(label: l10n.navProducts, value: '$totalProducts', icon: Icons.inventory_2_outlined, onTap: () => context.push(AppRoutes.products)),
                StatCard(label: l10n.navOrders, value: '$totalOrders', icon: Icons.receipt_long_outlined, onTap: () => context.push(AppRoutes.orders)),
                StatCard(label: l10n.navSales, value: totalSales.toStringAsFixed(0), icon: Icons.point_of_sale_outlined, onTap: () => context.push(AppRoutes.sales)),
              ],
            ),
            desktop: (context) => Row(
              children: [
                Expanded(child: StatCard(label: l10n.navProducts, value: '$totalProducts', icon: Icons.inventory_2_outlined, onTap: () => context.push(AppRoutes.products))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.navOrders, value: '$totalOrders', icon: Icons.receipt_long_outlined, onTap: () => context.push(AppRoutes.orders))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.navSales, value: totalSales.toStringAsFixed(0), icon: Icons.point_of_sale_outlined, onTap: () => context.push(AppRoutes.sales))),
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
            actions: [TextButton(onPressed: () => _openBusinesses(context, ref), child: Text(l10n.view))],
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

  /// Businesses/Active/Disabled drill into the same Businesses list their
  /// numbers were folded from (`adminBusinessListControllerProvider`) —
  /// Active/Disabled additionally pre-apply the real status filter the list
  /// already supports (`admin_repository.dart` reads
  /// `query.filters['status']`), so the count on the card and the rows the
  /// user lands on come from the exact same data, never a second
  /// hard-coded number. `context.go`, not `push`: these three stay inside
  /// the admin shell (a same-shell peer navigation, like the sidebar), no
  /// back-to-dashboard step is expected. Employees/Products/Orders/Sales
  /// are different — they `push` into the *business* shell's real screens
  /// (`_isAdminBrowsableRoute` in app_router.dart lets a System Admin
  /// session reach exactly those four routes) so the back arrow those
  /// screens gain when reached this way (`context.canPop()`) returns here.
  void _openBusinesses(BuildContext context, WidgetRef ref, {BusinessAccountStatus? status}) {
    ref.read(adminBusinessListControllerProvider.notifier).setFilters(status == null ? {} : {'status': status});
    context.go(AppRoutes.adminBusinesses);
  }
}
