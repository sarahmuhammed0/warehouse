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
import 'data/admin_metrics.dart';
import 'data/admin_providers.dart';
import 'presentation/admin_metric.dart';

/// The three cards on the second row. Employees sits on the first row next
/// to the business-account cards (it's a people statistic, not an
/// operational one) but drills down identically.
const _drilldownMetrics = [AdminMetric.products, AdminMetric.orders, AdminMetric.sales];

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
    // Every non-business figure here is derived from the real demo records
    // (`admin_metrics.dart`), never seeded onto the business row — so each
    // card's number is the sum of the per-business numbers the card's own
    // overview screen lists. While the aggregate is still loading the cards
    // show '—' rather than a zero that would read as a real total.
    final metrics = ref.watch(adminMetricsProvider).asData?.value;
    String total(AdminMetric metric) => metrics == null ? '—' : metric.totalLabel(metrics);

    return PageScaffold(
      title: l10n.adminNavDashboard,
      subtitle: l10n.demoDataNotice,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminDashboard,
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
                StatCard(label: l10n.navEmployees, value: total(AdminMetric.employees), icon: AdminMetric.employees.icon, onTap: () => context.push(AdminMetric.employees.overviewRoute)),
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
                Expanded(child: StatCard(label: l10n.navEmployees, value: total(AdminMetric.employees), icon: AdminMetric.employees.icon, onTap: () => context.push(AdminMetric.employees.overviewRoute))),
              ],
            ),
          ),
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                for (final metric in _drilldownMetrics)
                  StatCard(label: metric.label(l10n), value: total(metric), icon: metric.icon, onTap: () => context.push(metric.overviewRoute)),
              ],
            ),
            desktop: (context) => Row(
              children: [
                for (final metric in _drilldownMetrics) ...[
                  if (metric != _drilldownMetrics.first) const SizedBox(width: AppSpacing.md),
                  Expanded(child: StatCard(label: metric.label(l10n), value: total(metric), icon: metric.icon, onTap: () => context.push(metric.overviewRoute))),
                ],
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
  /// hard-coded number. These three are the exception to the drill-down
  /// rule on purpose: a *business* statistic's records ARE the business
  /// list, so there is no business left to choose. `context.go`, not
  /// `push`: they stay inside the admin shell as a peer navigation, like
  /// the sidebar.
  ///
  /// Employees/Products/Orders/Sales are records that belong to individual
  /// tenants, so they `push` into the metric's overview
  /// (`/admin/<metric>`) — the admin picks a business there, and only then
  /// sees that business's records. They never open the business shell's own
  /// operational tables; a System Admin session is redirected out of those
  /// (`app_router.dart`'s redirect) precisely so a platform statistic can't
  /// drop anyone into a warehouse's working screen.
  void _openBusinesses(BuildContext context, WidgetRef ref, {BusinessAccountStatus? status}) {
    ref.read(adminBusinessListControllerProvider.notifier).setFilters(status == null ? {} : {'status': status});
    context.go(AppRoutes.adminBusinesses);
  }
}
