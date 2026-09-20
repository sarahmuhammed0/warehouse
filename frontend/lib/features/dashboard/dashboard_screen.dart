import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/dashboard_containers.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/layout/responsive/responsive_layout.dart';
import '../../theme/app_spacing.dart';
import '../customers/data/customer_providers.dart';
import '../inventory/data/inventory_providers.dart';
import '../products/data/product_providers.dart';
import 'data/dashboard_widgets_controller.dart';

/// The real dashboard (spec §5), wired to the same demo repositories every
/// other module reads — no fabricated numbers: every stat below is a live
/// count/derivation over `LocalProductRepository`/`LocalCustomerRepository`/
/// etc., exactly the aggregation a real `/api/dashboard` endpoint would
/// return later (only the data source changes when that endpoint exists).
class DashboardPlaceholderScreen extends ConsumerWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final products = ref.watch(productPickerOptionsProvider);
    final customers = ref.watch(customerPickerOptionsProvider);
    final movements = ref.watch(movementListControllerProvider);
    final visible = ref.watch(dashboardWidgetsProvider);

    final productList = products.asData?.value ?? const [];
    final customerList = customers.asData?.value ?? const [];
    final lowStock = productList.where((p) => p.isLowStock).length;
    final outOfStock = productList.where((p) => p.isOutOfStock).length;
    final totalProducts = products.asData != null ? productList.length : null;
    final totalCustomers = customers.asData != null ? customerList.length : null;

    return PageScaffold(
      title: l10n.navDashboard,
      subtitle: l10n.demoDataNotice,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                StatCard(label: l10n.statTotalProducts, value: totalProducts?.toString() ?? '—', icon: Icons.inventory_2_outlined),
                if (visible.contains(DashboardWidget.customers))
                  StatCard(label: l10n.statTotalCustomers, value: totalCustomers?.toString() ?? '—', icon: Icons.people_outline),
                if (visible.contains(DashboardWidget.lowStock))
                  StatCard(label: l10n.statusLowStock, value: '$lowStock', icon: Icons.warning_amber_outlined, tone: Colors.orange),
                StatCard(label: l10n.statusOutOfStock, value: '$outOfStock', icon: Icons.remove_shopping_cart_outlined, tone: Colors.red),
              ],
            ),
            desktop: (context) => Row(
              children: [
                Expanded(child: StatCard(label: l10n.statTotalProducts, value: totalProducts?.toString() ?? '—', icon: Icons.inventory_2_outlined)),
                if (visible.contains(DashboardWidget.customers)) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: StatCard(label: l10n.statTotalCustomers, value: totalCustomers?.toString() ?? '—', icon: Icons.people_outline)),
                ],
                if (visible.contains(DashboardWidget.lowStock)) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: StatCard(label: l10n.statusLowStock, value: '$lowStock', icon: Icons.warning_amber_outlined, tone: Colors.orange)),
                ],
                const SizedBox(width: AppSpacing.md),
                Expanded(child: StatCard(label: l10n.statusOutOfStock, value: '$outOfStock', icon: Icons.remove_shopping_cart_outlined, tone: Colors.red)),
              ],
            ),
          ),
          ResponsiveLayout(
            mobile: (context) => Column(
              spacing: AppSpacing.md,
              children: [
                ChartContainer(title: l10n.dashboardKeyMetrics),
                _RecentMovements(movements: movements.items, l10n: l10n),
                if (visible.contains(DashboardWidget.alerts)) _LowStockAlerts(products: productList, l10n: l10n),
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
                      _RecentMovements(movements: movements.items, l10n: l10n),
                      if (visible.contains(DashboardWidget.alerts)) _LowStockAlerts(products: productList, l10n: l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppCardQuickActions(l10n: l10n),
        ],
      ),
    );
  }

}

class _RecentMovements extends StatelessWidget {
  const _RecentMovements({required this.movements, required this.l10n});
  final List<dynamic> movements;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ActivityListCard(
      title: l10n.dashboardRecentActivity,
      entries: [
        for (final m in movements.take(5))
          ActivityListEntry(title: '${m.productName} · ${m.previousQuantity} → ${m.newQuantity}', timestamp: '', icon: Icons.swap_vert),
      ],
      emptyLabel: l10n.dashboardNoActivityYet,
    );
  }
}

class _LowStockAlerts extends StatelessWidget {
  const _LowStockAlerts({required this.products, required this.l10n});
  final List<dynamic> products;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final alerting = products.where((p) => p.isLowStock || p.isOutOfStock).take(5).toList();
    return AlertCard(
      title: l10n.dashboardAlerts,
      alerts: [
        for (final p in alerting)
          AlertCardEntry(message: '${p.name}: ${p.currentQuantity} ${p.unit} left', icon: p.isOutOfStock ? Icons.remove_shopping_cart_outlined : Icons.warning_amber_outlined),
      ],
      emptyLabel: l10n.dashboardNoAlerts,
    );
  }
}

class AppCardQuickActions extends StatelessWidget {
  const AppCardQuickActions({super.key, required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: l10n.dashboardKeyMetrics,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          AppButton(label: '${l10n.add} ${l10n.navProducts}', icon: Icons.add, variant: AppButtonVariant.secondary, onPressed: () => context.push(AppRoutes.productNew)),
          AppButton(label: '${l10n.add} ${l10n.navCategories}', icon: Icons.add, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.categories)),
          AppButton(label: '${l10n.add} ${l10n.navSales}', icon: Icons.point_of_sale_outlined, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.sales)),
          AppButton(label: '${l10n.add} ${l10n.navCustomers}', icon: Icons.add, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.customers)),
          AppButton(label: '${l10n.add} ${l10n.navSuppliers}', icon: Icons.add, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.suppliers)),
          AppButton(label: l10n.generate, icon: Icons.bar_chart_outlined, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.reports)),
        ],
      ),
    );
  }
}
