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
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../auth/presentation/providers/permission_providers.dart';
import '../categories/presentation/category_form_dialog.dart';
import '../customers/presentation/customer_form_dialog.dart';
import '../inventory/presentation/stock_adjustment_dialog.dart';
import '../orders/data/order_models.dart';
import '../orders/data/order_providers.dart';
import '../products/data/product_providers.dart';
import '../suppliers/presentation/supplier_form_dialog.dart';
import 'data/dashboard_metrics.dart';

/// The business dashboard (spec §5), laid out as §5 defines it: main
/// statistics, visual reports, quick actions — plus the inventory alerts
/// §44 separately requires ("Show these on the dashboard").
///
/// **What this screen is not.** §6 defines the sidebar as the app's module
/// navigation, and this dashboard deliberately does not repeat it. A card
/// reading "Total products → Products" would be a second, worse copy of a
/// sidebar entry that is already one click away. The distinction the layout
/// holds to:
///
///   sidebar   — *where do I go?*
///   dashboard — *what is happening?*
///
/// So a KPI is tappable only where tapping **investigates that specific
/// number**: Low Stock opens Inventory filtered to low stock, Pending
/// Orders opens Orders filtered to Pending. Totals with no meaningful
/// filter behind them (Total products, Total customers, …) are
/// informational and are not dressed up as buttons.
///
/// The PDF itself is silent on dashboard-vs-sidebar duplication — it
/// neither requires module tiles nor forbids them — so this split is a UX
/// decision, recorded in `docs/business-dashboard-audit.md` as a decision
/// rather than presented as a spec requirement.
class DashboardPlaceholderScreen extends ConsumerWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final metrics = ref.watch(dashboardMetricsProvider).asData?.value;

    return PageScaffold(
      title: l10n.navDashboard,
      subtitle: l10n.demoDataNotice,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          // §5's quick actions — shortcuts into a workflow, placed where
          // they are reachable without scrolling past the statistics.
          _QuickActions(l10n: l10n),
          _Statistics(metrics: metrics, l10n: l10n),
          _Alerts(metrics: metrics, l10n: l10n),
          if (metrics != null)
            _ChartsCard(metrics: metrics, l10n: l10n)
          else
            SectionCard(title: l10n.dashboardKeyMetrics, child: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
          _RecentActivity(metrics: metrics, l10n: l10n),
        ],
      ),
    );
  }
}

/// §5's fifteen "main statistics", in the order the PDF lists them.
class _Statistics extends ConsumerWidget {
  const _Statistics({required this.metrics, required this.l10n});
  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While the aggregate loads, cards show '—' rather than a zero that
    // would read as a real "you have none".
    String n(int? value) => value?.toString() ?? '—';
    String money(double? value) => value?.toStringAsFixed(2) ?? '—';

    void openOrders(String route, {OrderStatus? status, String? period}) {
      ref.read(orderListControllerProvider.notifier).setFilters({
        'status': ?status,
        'period': ?period,
      });
      context.go(route);
    }

    // Low/out-of-stock open **Inventory**, not Products: the question
    // behind the number is a stock question, and Inventory is where stock
    // is acted on. Both screens read the same list controller, so the
    // filter applies either way.
    void openInventory(String stock) {
      ref.read(productListControllerProvider.notifier).setFilters({'stock': stock});
      context.go(AppRoutes.inventory);
    }

    final cards = <Widget>[
      _Stat(l10n.statTotalProducts, n(metrics?.totalProducts), Icons.inventory_2_outlined),
      _Stat(l10n.statTotalCategories, n(metrics?.totalCategories), Icons.category_outlined),
      _Stat(l10n.statTotalStock, n(metrics?.totalStockQuantity), Icons.warehouse_outlined),
      _Stat(l10n.statusLowStock, n(metrics?.lowStockCount), Icons.warning_amber_outlined,
          onTap: () => openInventory('low'), tone: Colors.orange),
      _Stat(l10n.statusOutOfStock, n(metrics?.outOfStockCount), Icons.remove_shopping_cart_outlined,
          onTap: () => openInventory('out'), tone: Colors.red),
      _Stat(l10n.statTodaysSales, money(metrics?.todaysSalesTotal), Icons.point_of_sale_outlined,
          onTap: () => openOrders(AppRoutes.sales, period: 'today')),
      _Stat(l10n.statTodaysOrders, n(metrics?.todaysOrderCount), Icons.receipt_long_outlined,
          onTap: () => openOrders(AppRoutes.orders, period: 'today')),
      _Stat(l10n.statMonthSales, money(metrics?.monthSalesTotal), Icons.calendar_month_outlined,
          onTap: () => openOrders(AppRoutes.sales, period: 'month')),
      // Total sales has no filter to drill into — "all sales" is the
      // unfiltered Sales list, which is the sidebar's job.
      _Stat(l10n.statTotalSales, money(metrics?.totalSalesTotal), Icons.summarize_outlined),
      _Stat(l10n.statPendingOrders, n(metrics?.pendingOrders), Icons.hourglass_empty,
          onTap: () => openOrders(AppRoutes.orders, status: OrderStatus.pending)),
      _Stat(l10n.statCompletedOrders, n(metrics?.completedOrders), Icons.check_circle_outline,
          onTap: () => openOrders(AppRoutes.orders, status: OrderStatus.completed)),
      _Stat(l10n.statCancelledOrders, n(metrics?.cancelledOrders), Icons.cancel_outlined,
          onTap: () => openOrders(AppRoutes.orders, status: OrderStatus.cancelled)),
      _Stat(l10n.statReturnedOrders, n(metrics?.returnedOrders), Icons.assignment_return_outlined,
          onTap: () => openOrders(AppRoutes.orders, status: OrderStatus.returned)),
      _Stat(l10n.statTotalCustomers, n(metrics?.totalCustomers), Icons.people_outline),
      _Stat(l10n.statTotalSuppliers, n(metrics?.totalSuppliers), Icons.local_shipping_outlined),
      // §5 lists profit as a chart subject, "if cost prices are available".
      // Shown as a figure too when it is known; omitted rather than zeroed
      // when no product carries a cost, since 0 would read as "you made
      // nothing" rather than "this isn't known".
      if (metrics?.grossProfit != null)
        _Stat(l10n.statGrossProfit, money(metrics!.grossProfit), Icons.trending_up),
    ];

    return LayoutBuilder(
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
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, {this.onTap, this.tone});

  final String label;
  final String value;
  final IconData icon;

  /// `null` means informational. A card is not made tappable just to look
  /// interactive — §4's "do NOT make cards clickable just for decoration".
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) => StatCard(label: label, value: value, icon: icon, tone: tone, onTap: onTap);
}

/// Spec §44 ("Inventory alerts") ends with "Show these on the dashboard",
/// which is the only place the PDF asks for a dashboard alert block. Low
/// stock, out of stock and overstock come straight from §44's own
/// definitions; pending orders and pending payments are the two other
/// things a business owner needs pushed at them rather than gone looking
/// for. Each row drills into the records behind it.
class _Alerts extends ConsumerWidget {
  const _Alerts({required this.metrics, required this.l10n});
  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final m = metrics;

    void openInventory(String stock) {
      ref.read(productListControllerProvider.notifier).setFilters({'stock': stock});
      context.go(AppRoutes.inventory);
    }

    void openOrders({OrderStatus? status}) {
      ref.read(orderListControllerProvider.notifier).setFilters({'status': ?status});
      context.go(AppRoutes.orders);
    }

    final rows = <_AlertRow>[
      if ((m?.outOfStockCount ?? 0) > 0)
        _AlertRow(l10n.statusOutOfStock, m!.outOfStockCount, Icons.remove_shopping_cart_outlined, colors.error, () => openInventory('out')),
      if ((m?.lowStockCount ?? 0) > 0)
        _AlertRow(l10n.statusLowStock, m!.lowStockCount, Icons.warning_amber_outlined, colors.warning, () => openInventory('low')),
      if ((m?.overstockCount ?? 0) > 0)
        _AlertRow(l10n.alertOverstock, m!.overstockCount, Icons.inbox_outlined, colors.info, () => context.go(AppRoutes.inventory)),
      if ((m?.pendingOrders ?? 0) > 0)
        _AlertRow(l10n.statPendingOrders, m!.pendingOrders, Icons.hourglass_empty, colors.warning, () => openOrders(status: OrderStatus.pending)),
      if ((m?.unpaidOrderCount ?? 0) > 0)
        _AlertRow(l10n.alertPendingPayments, m!.unpaidOrderCount, Icons.account_balance_wallet_outlined, colors.warning, () => openOrders()),
    ];

    return SectionCard(
      title: l10n.dashboardAlerts,
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                m == null ? l10n.loading : l10n.alertNoneTitle,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  InkWell(
                    onTap: row.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(row.icon, size: 18, color: row.tone),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(row.label, style: AppTypography.body.copyWith(color: colors.textPrimary))),
                          Text('${row.count}', style: AppTypography.bodyStrong.copyWith(color: row.tone)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AlertRow {
  const _AlertRow(this.label, this.count, this.icon, this.tone, this.onTap);
  final String label;
  final int count;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;
}

/// §5's "visual reports" — all ten subjects the PDF lists, each over real
/// demo data. The panel this replaced rendered the literal sentence
/// "Chart will render here once connected to real data" while every number
/// it needed was already in the repositories.
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
    final m = widget.metrics;
    // Order matches §5's own list, so the tabs can be checked against the
    // PDF line by line.
    final series = <(String, List<ChartPoint>)>[
      (l10n.chartDailySales, m.dailySales),
      (l10n.chartWeeklySales, m.weeklySales),
      (l10n.chartMonthlySales, m.monthlySales),
      (l10n.chartYearlySales, m.yearlySales),
      (l10n.chartTopProducts, m.topProducts),
      (l10n.chartCategorySales, m.categorySales),
      (l10n.reportStockMovement, m.stockMovement),
      (l10n.chartPurchases, m.purchases),
      (l10n.chartReturns, m.returns),
      // Profit only when cost prices exist — §5's own condition.
      if (m.profitByMonth.isNotEmpty) (l10n.chartProfit, m.profitByMonth),
    ];
    final current = series[_selected.clamp(0, series.length - 1)];

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
                    key: ValueKey('chartTab${series[i].$1}'),
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

/// §5's quick actions — "Buttons such as:" in the PDF, so examples rather
/// than a fixed list. Each one opens the workflow it names; none is a
/// module shortcut (that is the sidebar's job). Permission-gated, so a
/// Sales Staff identity is not offered "Add product".
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

/// Real business events across modules, newest first — stock movements,
/// orders, returns, purchases and production runs, each opening the record
/// it describes. Built from actual records rather than seeded filler: if
/// the demo data has no returns, none appear.
class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.metrics, required this.l10n});
  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final entries = metrics?.recentActivity ?? const <ActivityEntry>[];
    final colors = context.colors;

    return SectionCard(
      title: l10n.dashboardRecentActivity,
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(l10n.dashboardNoActivityYet, style: AppTypography.body.copyWith(color: colors.textMuted)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries.take(8))
                  InkWell(
                    onTap: () => context.push(entry.route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: colors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(entry.description, style: AppTypography.body.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis)),
                          Text(_relative(entry.at), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _relative(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
