import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_icon_chip.dart';
import '../../shared/cards/brand_panel.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/date_range_chip.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/dashboard/simple_bar_chart.dart';
import '../../shared/dashboard/vertical_bar_chart.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../auth/presentation/providers/auth_controller.dart';
import '../auth/presentation/providers/auth_state.dart';
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
class DashboardPlaceholderScreen extends ConsumerStatefulWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  ConsumerState<DashboardPlaceholderScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardPlaceholderScreen> {
  OverviewRange _range = OverviewRange.months;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final metrics = ref.watch(dashboardMetricsProvider).asData?.value;
    final authState = ref.watch(authControllerProvider);
    final accountName = authState is AuthAuthenticated ? authState.account.name : null;
    final permissions = ref.watch(currentPermissionsProvider);

    return PageScaffold(
      title: l10n.navDashboard,
      titleWidget: _Greeting(name: accountName, fallback: l10n.navDashboard),
      subtitle: l10n.demoDataNotice,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      secondaryActions: [
        DateRangeChip<OverviewRange>(
          key: const ValueKey('dashboardRangeChip'),
          options: [
            (value: OverviewRange.days, label: l10n.chartDailySales),
            (value: OverviewRange.weeks, label: l10n.chartWeeklySales),
            (value: OverviewRange.months, label: l10n.chartMonthlySales),
          ],
          selected: _range,
          span: _range.spanOf(metrics),
          onChanged: (value) => setState(() => _range = value),
        ),
      ],
      primaryAction: hasPermission(permissions, 'sales', 'create')
          ? AppButton(
              label: l10n.actionNewSale,
              icon: Icons.add,
              onPressed: () => context.push(AppRoutes.saleNew),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        // Order: overview row → statistics → alerts → report charts →
        // recent activity → quick actions. The monitoring content comes
        // first and the shortcuts sit at the very bottom; nothing follows
        // them but page padding.
        children: [
          _OverviewRow(metrics: metrics, l10n: l10n, range: _range),
          _Statistics(metrics: metrics, l10n: l10n),
          _Alerts(metrics: metrics, l10n: l10n),
          if (metrics != null)
            _ChartsCard(metrics: metrics, l10n: l10n)
          else
            SectionCard(
              title: l10n.dashboardKeyMetrics,
              child: const Center(
                child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
              ),
            ),
          _RecentActivity(metrics: metrics, l10n: l10n),
          // §5's quick actions — the last major section on the page.
          _QuickActions(l10n: l10n),
        ],
      ),
    );
  }
}

enum OverviewRange {
  days,
  weeks,
  months;

  List<ChartPoint> seriesOf(DashboardMetrics? m) => switch (this) {
        OverviewRange.days => m?.dailySales ?? const [],
        OverviewRange.weeks => m?.weeklySales ?? const [],
        OverviewRange.months => m?.monthlySales ?? const [],
      };

  String labelOf(AppLocalizations l10n) => switch (this) {
        OverviewRange.days => l10n.chartDailySales,
        OverviewRange.weeks => l10n.chartWeeklySales,
        OverviewRange.months => l10n.chartMonthlySales,
      };

  /// The first and last point the chosen series plots, so the control can
  /// state the dates it actually covers rather than only its own name.
  String? spanOf(DashboardMetrics? m) {
    final series = seriesOf(m);
    if (series.isEmpty) return null;
    return '${series.first.label} — ${series.last.label}';
  }
}

/// The dashboard's two-tone greeting — the page's name in full strength,
/// who is signed in beside it in muted weight. Falls back to the plain
/// page title when there is no session name to greet, so the header never
/// renders a dangling comma.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.fallback});

  final String? name;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.displayTitle;

    if (name == null) {
      return Text(fallback, style: style.copyWith(color: colors.textPrimary));
    }

    return RichText(
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      text: TextSpan(
        style: style.copyWith(color: colors.textPrimary),
        children: [
          TextSpan(text: '${AppLocalizations.of(context)!.dashboardWelcomeBack} '),
          TextSpan(text: name!, style: style.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

/// The overview row — the three cards the reference design leads with:
/// today's revenue on the brand panel, a sales-overview chart, and the
/// money still owed.
///
/// Today's revenue is also one of the six stat cards below, and that
/// repetition is the point of a headline: the grid answers "what are all
/// the numbers", this answers "what is today". Everything else in the row
/// — the overview series, outstanding payments, the pending counts — is
/// not otherwise on screen, so the row adds information rather than only
/// restating it.
///
/// Three across on a desktop, stacked below that. It sits *above* the stat
/// grid but deliberately holds no `StatCard`: these are feature cards, and
/// mixing them into the grid's rhythm would flatten both.
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.metrics, required this.l10n, required this.range});

  final DashboardMetrics? metrics;
  final AppLocalizations l10n;
  final OverviewRange range;

  /// Card chrome (padding + header) plus the chart, which is the tallest
  /// of the three contents. Shared with [_SalesOverviewCard] so the chart
  /// and the box it sits in cannot drift apart.
  static const double chartHeight = 190;
  static const double _rowHeight = chartHeight + 96;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _TodaysSalesCard(metrics: metrics, l10n: l10n),
      _SalesOverviewCard(metrics: metrics, l10n: l10n, range: range),
      _OutstandingCard(metrics: metrics, l10n: l10n),
    ];

    // Decided from the window, not measured with a `LayoutBuilder`. A
    // LayoutBuilder builds its subtree *during* layout, and a subtree that
    // large — three cards, a chart, a gradient panel — is exactly the kind
    // that then trips Flutter's "built during layout" assertions on the
    // web renderer, where fonts arriving late force a second layout pass.
    // The window width is known before layout starts and answers the same
    // question.
    if (MediaQuery.sizeOf(context).width < 1180) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: cards,
      );
    }

    // The chart earns the extra width — it is the only one of the three
    // plotting a series rather than showing one figure.
    //
    // A fixed row height, not `IntrinsicHeight`: the three cards have to
    // line up, and `IntrinsicHeight` cannot measure a subtree that builds
    // during layout. The height comes from the tallest card's content (the
    // chart) rather than being discovered.
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: cards[0]),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 5, child: cards[1]),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 3, child: cards[2]),
        ],
      ),
    );
  }
}

/// The reference's signature card: a titled white card whose content is a
/// deep-blue panel carrying the day's revenue.
class _TodaysSalesCard extends ConsumerWidget {
  const _TodaysSalesCard({required this.metrics, required this.l10n});

  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  static String _today() {
    final now = DateTime.now();
    // Same hand-built ISO shape every other date in the app uses — the
    // one format that reads identically under English, Arabic and Kurdish.
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final businessName = authState is AuthAuthenticated
        ? (authState.business?.name ?? authState.account.name)
        : l10n.appName;
    final m = metrics;

    return SectionCard(
      title: l10n.statTodaysSales,
      padding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        AppCircleButton(
          icon: Icons.arrow_outward,
          tooltip: l10n.view,
          onPressed: () => context.go(AppRoutes.sales),
        ),
      ],
      child: BrandPanel(
        eyebrow: businessName,
        label: l10n.reportRevenue,
        value: m?.todaysSalesTotal.toStringAsFixed(2) ?? '—',
        footnote: m == null
            ? null
            : '${m.todaysOrderCount} ${l10n.navOrders} · ${m.pendingOrders} ${l10n.statusPending}',
        trailing: _today(),
      ),
    );
  }
}

/// The reference's "Sales Overview" — one series, switchable between two
/// ranges, plotted as columns. Distinct from the full report chart further
/// down the page: this one answers "how is the trend", that one is §5's
/// ten-subject report switcher.
class _SalesOverviewCard extends StatefulWidget {
  const _SalesOverviewCard({required this.metrics, required this.l10n, required this.range});

  final DashboardMetrics? metrics;
  final AppLocalizations l10n;
  final OverviewRange range;

  @override
  State<_SalesOverviewCard> createState() => _SalesOverviewCardState();
}

class _SalesOverviewCardState extends State<_SalesOverviewCard> {
  int? _selected;

  @override
  void didUpdateWidget(_SalesOverviewCard old) {
    super.didUpdateWidget(old);
    // A new period is a new series of a different length; keeping the old
    // index would pick out an unrelated bar.
    if (old.range != widget.range) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final series = widget.range.seriesOf(widget.metrics);

    return SectionCard(
      title: l10n.reportRevenue,
      subtitle: widget.range.labelOf(l10n),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: VerticalBarChart(
        points: [for (final p in series) (label: p.label, value: p.value)],
        emptyLabel: l10n.dashboardNoChartData,
        height: _OverviewRow.chartHeight,
        valueFormatter: (v) => v.toStringAsFixed(0),
        selectedIndex: _selected,
        onSelected: (i) => setState(() => _selected = i),
      ),
    );
  }
}

/// Money owed to the business — the reference's "Outstanding Payments",
/// with the count as a pill beside the figure and the trend beneath it.
class _OutstandingCard extends ConsumerWidget {
  const _OutstandingCard({required this.metrics, required this.l10n});

  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final m = metrics;

    return SectionCard(
      title: l10n.alertPendingPayments,
      icon: Icons.account_balance_wallet_outlined,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: SplitValueText(
                  value: m?.unpaidTotal.toStringAsFixed(2) ?? '—',
                  style: AppTypography.kpiValueLarge,
                  color: colors.textPrimary,
                ),
              ),
              if (m != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: StatusPill(
                    label: '${m.unpaidOrderCount} ${l10n.navOrders}',
                    color: m.unpaidOrderCount > 0 ? colors.warning : colors.success,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The trend behind the figure, not a second set of numbers —
          // the monthly series it is drawn from is charted in full beside
          // this card.
          Sparkline(values: [for (final p in m?.monthlySales ?? const <ChartPoint>[]) p.value]),
        ],
      ),
    );
  }
}

/// §5's fifteen "main statistics", split into what a business owner needs
/// *today* and what they occasionally look up.
///
/// All fifteen are here — §5 requires them and none was dropped. But
/// fifteen equal-weight cards is a wall of numbers with no shape, and the
/// three or four that actually need acting on are lost in it. So the
/// headline row is exactly the figures that **need attention or action
/// today**, and by construction every one of them drills into its own
/// records:
///
///   Today's sales · Today's orders · This month's sales
///   Pending orders · Low stock · Out of stock
///
/// The remaining nine are reference figures — totals that barely move
/// day to day, and the closed-order counts — behind one tap. They keep
/// their drill-downs where they had one.
class _Statistics extends ConsumerStatefulWidget {
  const _Statistics({required this.metrics, required this.l10n});
  final DashboardMetrics? metrics;
  final AppLocalizations l10n;

  @override
  ConsumerState<_Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends ConsumerState<_Statistics> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final colors = context.colors;
    final metrics = widget.metrics;
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

    // The six the dashboard leads with. Four of them drill into their own
    // records; Total products and Total stock quantity are informational,
    // since "all products" is the unfiltered Products list and that is the
    // sidebar's job.
    final headline = <Widget>[
      _Stat(l10n.statusLowStock, n(metrics?.lowStockCount), Icons.warning_amber_outlined,
          onTap: () => openInventory('low'), tone: colors.warning),
      _Stat(l10n.statusOutOfStock, n(metrics?.outOfStockCount), Icons.remove_shopping_cart_outlined,
          onTap: () => openInventory('out'), tone: colors.error),
      _Stat(l10n.statPendingOrders, n(metrics?.pendingOrders), Icons.hourglass_empty,
          onTap: () => openOrders(AppRoutes.orders, status: OrderStatus.pending)),
      _Stat(l10n.statTodaysOrders, n(metrics?.todaysOrderCount), Icons.receipt_long_outlined,
          onTap: () => openOrders(AppRoutes.orders, period: 'today')),
    ];

    // Reference figures. Still §5-required, still exact, just not shouting.
    final secondary = <Widget>[
      _Stat(l10n.statTotalProducts, n(metrics?.totalProducts), Icons.inventory_2_outlined),
      _Stat(l10n.statTotalStock, n(metrics?.totalStockQuantity), Icons.warehouse_outlined),
      _Stat(l10n.statTodaysSales, money(metrics?.todaysSalesTotal), Icons.point_of_sale_outlined,
          onTap: () => openOrders(AppRoutes.sales, period: 'today')),
      _Stat(l10n.statTotalCategories, n(metrics?.totalCategories), Icons.category_outlined),
      _Stat(l10n.statMonthSales, money(metrics?.monthSalesTotal), Icons.calendar_month_outlined,
          onTap: () => openOrders(AppRoutes.sales, period: 'month')),
      // Total sales has no filter to drill into — "all sales" is the
      // unfiltered Sales list, which is the sidebar's job.
      _Stat(l10n.statTotalSales, money(metrics?.totalSalesTotal), Icons.summarize_outlined),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        _StatGrid(cards: headline),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _MoreToggle(
            key: const ValueKey('toggleMoreStatistics'),
            expanded: _expanded,
            label: _expanded
                ? l10n.dashboardFewerStatistics
                : l10n.dashboardMoreStatistics(secondary.length),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded) _StatGrid(cards: secondary),
      ],
    );
  }
}

/// The "More statistics (10)" control. A pill rather than a bare text
/// button: it sits between two grids of cards, and an unenclosed text link
/// there reads as a stray caption rather than as the control that reveals
/// the rest of the numbers.
class _MoreToggle extends StatelessWidget {
  const _MoreToggle({super.key, required this.expanded, required this.label, required this.onTap});

  final bool expanded;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.accentSoft,
      borderRadius: AppRadius.pillRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: AppTypography.button.copyWith(color: colors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The responsive card grid both statistic rows use — 4 columns on a
/// desktop, 2 on a tablet, 1 on a phone.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
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
  Widget build(BuildContext context) =>
      StatCard(label: label, value: value, icon: icon, tone: tone, onTap: onTap);
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
        _AlertRow(l10n.statusOutOfStock, m!.outOfStockCount, Icons.remove_shopping_cart_outlined,
            colors.error, () => openInventory('out')),
      if ((m?.lowStockCount ?? 0) > 0)
        _AlertRow(l10n.statusLowStock, m!.lowStockCount, Icons.warning_amber_outlined,
            colors.warning, () => openInventory('low')),
      if ((m?.overstockCount ?? 0) > 0)
        _AlertRow(l10n.alertOverstock, m!.overstockCount, Icons.inbox_outlined, colors.info,
            () => context.go(AppRoutes.inventory)),
      if ((m?.pendingOrders ?? 0) > 0)
        _AlertRow(l10n.statPendingOrders, m!.pendingOrders, Icons.hourglass_empty, colors.warning,
            () => openOrders(status: OrderStatus.pending)),
      if ((m?.unpaidOrderCount ?? 0) > 0)
        _AlertRow(l10n.alertPendingPayments, m!.unpaidOrderCount,
            Icons.account_balance_wallet_outlined, colors.warning, () => openOrders()),
    ];

    return SectionCard(
      title: l10n.dashboardAlerts,
      icon: Icons.notifications_active_outlined,
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
                  CardListRow(
                    label: row.label,
                    icon: row.icon,
                    tone: row.tone,
                    trailingText: '${row.count}',
                    trailingColor: row.tone,
                    onTap: row.onTap,
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
/// demo data.
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
      icon: Icons.bar_chart_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          // Ten subjects is more than a segmented control can hold, so the
          // series picker stays a scrolling row of pills — the same pill
          // language, sized for a list that does not fit.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < series.length; i++)
                  _SeriesPill(
                    key: ValueKey('chartTab${series[i].$1}'),
                    label: series[i].$1,
                    selected: _selected == i,
                    onTap: () => setState(() => _selected = i),
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

/// One chart-series selector. Replaces Material's `ChoiceChip`, whose
/// checkmark, border and ripple made a row of ten of them noisy — this is
/// the same pill the rest of the design system uses.
class _SeriesPill extends StatelessWidget {
  const _SeriesPill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.primary : colors.surfaceMuted,
      borderRadius: AppRadius.pillRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 15, color: colors.onPrimary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTypography.button.copyWith(
                  color: selected ? colors.onPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
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
      icon: Icons.bolt_outlined,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          if (hasPermission(permissions, 'products', 'create'))
            AppButton(
              key: const ValueKey('quickAddProduct'),
              label: '${l10n.add} ${l10n.navProducts}',
              icon: Icons.add,
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.productNew),
            ),
          if (hasPermission(permissions, 'categories', 'create'))
            AppButton(
              key: const ValueKey('quickAddCategory'),
              label: '${l10n.add} ${l10n.navCategories}',
              icon: Icons.add,
              size: AppButtonSize.small,
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
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.saleNew),
            ),
          if (hasPermission(permissions, 'orders', 'create'))
            AppButton(
              key: const ValueKey('quickNewOrder'),
              label: l10n.actionNewOrder,
              icon: Icons.receipt_long_outlined,
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.orderNew),
            ),
          if (hasPermission(permissions, 'inventory', 'edit'))
            AppButton(
              key: const ValueKey('quickAddStock'),
              label: l10n.actionAddStock,
              icon: Icons.add_box_outlined,
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () => showStockAdjustmentDialog(context),
            ),
          if (hasPermission(permissions, 'customers', 'create'))
            AppButton(
              key: const ValueKey('quickAddCustomer'),
              label: '${l10n.add} ${l10n.navCustomers}',
              icon: Icons.add,
              size: AppButtonSize.small,
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
              size: AppButtonSize.small,
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
              size: AppButtonSize.small,
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
      icon: Icons.history,
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                l10n.dashboardNoActivityYet,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries.take(8))
                  CardListRow(
                    label: entry.description,
                    icon: Icons.circle,
                    iconSize: 7,
                    tone: colors.primary,
                    trailingText: _relative(entry.at),
                    trailingColor: colors.textMuted,
                    trailingStrong: false,
                    onTap: () => context.push(entry.route),
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
