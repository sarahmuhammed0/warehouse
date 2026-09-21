import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/dashboard/simple_bar_chart.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../theme/app_spacing.dart';
import '../auth/presentation/providers/permission_providers.dart';
import '../categories/presentation/category_form_dialog.dart';
import '../customers/presentation/customer_form_dialog.dart';
import '../inventory/data/inventory_providers.dart';
import '../inventory/presentation/stock_adjustment_dialog.dart';
import '../orders/data/order_models.dart';
import '../orders/data/order_providers.dart';
import '../products/data/product_providers.dart';
import '../suppliers/presentation/supplier_form_dialog.dart';
import 'data/dashboard_metrics.dart';
import 'data/dashboard_widgets_controller.dart';

/// The business dashboard (spec §5): statistics, visual reports and quick
/// actions — all three real.
///
/// Every number comes from `dashboardMetricsProvider`, which derives it from
/// the same demo repositories the modules read. Every card is a drill-down
/// that pre-applies the filter its own number was counted with, so tapping
/// "Pending orders: 3" lands on exactly those three rows — the same rule the
/// System Admin dashboard follows.
class DashboardPlaceholderScreen extends ConsumerWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final metrics = metricsAsync.asData?.value;
    final movements = ref.watch(movementListControllerProvider);
    final products = ref.watch(productPickerOptionsProvider).asData?.value ?? const [];
    final visible = ref.watch(dashboardWidgetsProvider);

    // While the aggregate loads, cards show '—' rather than a zero that
    // would read as a real "you have none".
    String n(int? value) => value?.toString() ?? '—';
    String money(double? value) => value?.toStringAsFixed(2) ?? '—';

    final cards = <Widget>[
      _Stat(l10n.statTotalProducts, n(metrics?.totalProducts), Icons.inventory_2_outlined, () => _openProducts(context, ref)),
      _Stat(l10n.statTotalCategories, n(metrics?.totalCategories), Icons.category_outlined, () => context.go(AppRoutes.categories)),
      _Stat(l10n.statTotalStock, n(metrics?.totalStockQuantity), Icons.warehouse_outlined, () => context.go(AppRoutes.inventory)),
      if (visible.contains(DashboardWidget.lowStock))
        _Stat(l10n.statusLowStock, n(metrics?.lowStockCount), Icons.warning_amber_outlined, () => _openProducts(context, ref, stock: 'low'), Colors.orange),
      _Stat(l10n.statusOutOfStock, n(metrics?.outOfStockCount), Icons.remove_shopping_cart_outlined, () => _openProducts(context, ref, stock: 'out'), Colors.red),
      _Stat(l10n.statTodaysSales, money(metrics?.todaysSalesTotal), Icons.point_of_sale_outlined, () => _openOrders(context, ref, AppRoutes.sales, period: 'today')),
      _Stat(l10n.statTodaysOrders, n(metrics?.todaysOrderCount), Icons.receipt_long_outlined, () => _openOrders(context, ref, AppRoutes.orders, period: 'today')),
      _Stat(l10n.statMonthSales, money(metrics?.monthSalesTotal), Icons.calendar_month_outlined, () => _openOrders(context, ref, AppRoutes.sales, period: 'month')),
      _Stat(l10n.statTotalSales, money(metrics?.totalSalesTotal), Icons.summarize_outlined, () => _openOrders(context, ref, AppRoutes.sales)),
      _Stat(l10n.statPendingOrders, n(metrics?.pendingOrders), Icons.hourglass_empty, () => _openOrders(context, ref, AppRoutes.orders, status: OrderStatus.pending)),
      _Stat(l10n.statCompletedOrders, n(metrics?.completedOrders), Icons.check_circle_outline, () => _openOrders(context, ref, AppRoutes.orders, status: OrderStatus.completed)),
      _Stat(l10n.statCancelledOrders, n(metrics?.cancelledOrders), Icons.cancel_outlined, () => _openOrders(context, ref, AppRoutes.orders, status: OrderStatus.cancelled)),
      _Stat(l10n.statReturnedOrders, n(metrics?.returnedOrders), Icons.assignment_return_outlined, () => _openOrders(context, ref, AppRoutes.orders, status: OrderStatus.returned)),
      if (visible.contains(DashboardWidget.customers))
        _Stat(l10n.statTotalCustomers, n(metrics?.totalCustomers), Icons.people_outline, () => context.go(AppRoutes.customers)),
      _Stat(l10n.statTotalSuppliers, n(metrics?.totalSuppliers), Icons.local_shipping_outlined, () => context.go(AppRoutes.suppliers)),
      // Profit is shown only when some product carries a cost — §5 asks for
      // it "when cost data exists", and a 0 would read as "you made nothing"
      // rather than "this isn't known".
      if (metrics?.grossProfit != null)
        _Stat(l10n.statGrossProfit, money(metrics!.grossProfit), Icons.trending_up, () => context.go(AppRoutes.reports)),
    ];

    return PageScaffold(
      title: l10n.navDashboard,
      subtitle: l10n.demoDataNotice,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          // A Wrap rather than fixed Rows: fifteen cards can't be a single
          // row at any width, and this degrades cleanly from desktop to
          // phone without a breakpoint table.
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1100
                  ? 4
                  : constraints.maxWidth > 700
                      ? 2
                      : 1;
              final width = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [for (final card in cards) SizedBox(width: width, child: card)],
              );
            },
          ),
          if (metrics != null)
            _ChartsCard(metrics: metrics, l10n: l10n)
          else
            SectionCard(title: l10n.dashboardKeyMetrics, child: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
          _QuickActions(l10n: l10n),
          _RecentMovements(movements: movements.items, l10n: l10n),
          if (visible.contains(DashboardWidget.alerts)) _LowStockAlerts(products: products, l10n: l10n),
        ],
      ),
    );
  }

  /// Drill-downs pre-apply the filter the card's own number was counted
  /// with, so the list a user lands on is exactly the rows behind the
  /// figure they tapped — never a same-module page showing something else.
  void _openProducts(BuildContext context, WidgetRef ref, {String? stock}) {
    ref.read(productListControllerProvider.notifier).setFilters(stock == null ? {} : {'stock': stock});
    context.go(AppRoutes.products);
  }

  void _openOrders(BuildContext context, WidgetRef ref, String route, {OrderStatus? status, String? period}) {
    ref.read(orderListControllerProvider.notifier).setFilters({
      'status': ?status,
      'period': ?period,
    });
    context.go(route);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.onTap, [this.tone]);

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) => StatCard(label: label, value: value, icon: icon, tone: tone, onTap: onTap);
}

/// §5's "visual reports", over real numbers. Four series the demo data can
/// actually support; the card that used to sit here rendered the literal
/// text "Chart will render here once connected to real data" while the data
/// was sitting in the repositories the whole time.
class _ChartsCard extends StatefulWidget {
  const _ChartsCard({required this.metrics, required this.l10n});
  final DashboardMetrics metrics;
  final AppLocalizations l10n;

  @override
  State<_ChartsCard> createState() => _ChartsCardState();
}

class _ChartsCardState extends State<_ChartsCard> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final series = <(String, List<ChartPoint>, bool)>[
      (l10n.chartDailySales, widget.metrics.dailySales, true),
      (l10n.chartMonthlySales, widget.metrics.monthlySales, true),
      (l10n.chartTopProducts, widget.metrics.topProducts, true),
      (l10n.chartCategorySales, widget.metrics.categorySales, true),
    ];
    final current = series[_selected];

    return SectionCard(
      title: current.$1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < series.length; i++)
                  ChoiceChip(
                    label: Text(series[i].$1),
                    selected: _selected == i,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
          ),
          SimpleBarChart(
            points: [for (final p in current.$2) (label: p.label, value: p.value)],
            emptyLabel: l10n.dashboardNoChartData,
            valueFormatter: (v) => v.toStringAsFixed(2),
          ),
        ],
      ),
    );
  }
}

/// §5's quick actions. Each opens the workflow it names — a create form or
/// a create dialog — rather than dropping the user on a list screen to find
/// the Add button themselves, which is what four of these used to do.
/// Permission-gated: a Sales Staff identity has no business seeing "Add
/// product" (spec §24, see permission_providers.dart).
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(currentPermissionsProvider);

    return SectionCard(
      title: l10n.dashboardQuickActions,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          if (hasPermission(permissions, 'products', 'create'))
            AppButton(
              key: const ValueKey('quickAddProduct'),
              label: '${l10n.add} ${l10n.navProducts}',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.productNew),
            ),
          if (hasPermission(permissions, 'categories', 'create'))
            AppButton(
              key: const ValueKey('quickAddCategory'),
              label: '${l10n.add} ${l10n.navCategories}',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              // Categories are created through a dialog on their own screen;
              // opening that dialog straight from here is the same workflow
              // without the detour.
              onPressed: () async {
                final created = await showCategoryFormDialog(context);
                if ((created ?? false) && context.mounted) context.go(AppRoutes.categories);
              },
            ),
          if (hasPermission(permissions, 'sales', 'create'))
            AppButton(
              key: const ValueKey('quickNewSale'),
              label: l10n.actionNewSale,
              icon: Icons.point_of_sale_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.saleNew),
            ),
          if (hasPermission(permissions, 'orders', 'create'))
            AppButton(
              key: const ValueKey('quickNewOrder'),
              label: l10n.actionNewOrder,
              icon: Icons.receipt_long_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.orderNew),
            ),
          if (hasPermission(permissions, 'inventory', 'edit'))
            AppButton(
              key: const ValueKey('quickAddStock'),
              label: l10n.actionAddStock,
              icon: Icons.add_box_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => showStockAdjustmentDialog(context),
            ),
          if (hasPermission(permissions, 'customers', 'create'))
            AppButton(
              key: const ValueKey('quickAddCustomer'),
              label: '${l10n.add} ${l10n.navCustomers}',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                final created = await showCustomerFormDialog(context);
                if ((created ?? false) && context.mounted) context.go(AppRoutes.customers);
              },
            ),
          if (hasPermission(permissions, 'suppliers', 'create'))
            AppButton(
              key: const ValueKey('quickAddSupplier'),
              label: '${l10n.add} ${l10n.navSuppliers}',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                final created = await showSupplierFormDialog(context);
                if ((created ?? false) && context.mounted) context.go(AppRoutes.suppliers);
              },
            ),
          if (hasPermission(permissions, 'reports', 'view'))
            AppButton(
              key: const ValueKey('quickGenerateReport'),
              label: l10n.generate,
              icon: Icons.bar_chart_outlined,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.reports),
            ),
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
