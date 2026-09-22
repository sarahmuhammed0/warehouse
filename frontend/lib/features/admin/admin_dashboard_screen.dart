import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/cards/app_icon_chip.dart';
import '../../shared/cards/brand_panel.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/date_range_chip.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/feedback/app_toast.dart';
import '../../shared/dashboard/vertical_bar_chart.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/navigation/nav_items.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../auth/presentation/providers/auth_controller.dart';
import '../auth/presentation/providers/auth_state.dart';
import 'data/admin_business_models.dart';
import 'data/admin_metrics.dart';
import 'data/admin_providers.dart';
import 'presentation/admin_metric.dart';

/// The three record metrics that sit in the tile row. Employees is the one
/// people statistic and heads the left column instead, but drills down
/// identically.
const _tileMetrics = [AdminMetric.products, AdminMetric.orders, AdminMetric.sales];

/// System Admin dashboard (spec §2/§36) — cross-tenant aggregate stats.
///
/// Shares the business dashboard's design system exactly — same cards,
/// pills, typography and brand panel — but says what it is. The panel is a
/// platform panel, the figures are cross-tenant, and nothing here opens a
/// single business's operational screens (§10: "System Admin is GLOBAL,
/// business UI is BUSINESS-SPECIFIC; do not mix the two").
///
/// **On the figures that are not here.** The reference design carries an
/// API-uptime card and a backup card. This frontend runs in demo mode with
/// the backend off, and `system_status` reads uptime from a real
/// `/api/health` call — so an uptime percentage here would be a number
/// nobody measured, and there is no backup subsystem at all. Their slots
/// carry platform figures that *are* derived from real records: account
/// health, and the platform's own activity.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

/// How many of the tracked months the platform chart plots.
enum AdminRange {
  threeMonths(3),
  sixMonths(6),
  twelveMonths(12);

  const AdminRange(this.months);
  final int months;

  /// A tail of the tracked series — never a re-query, so every range is
  /// folded from the same single pass over the records.
  List<({String label, double value})> tailOf(List<({String label, double value})> all) =>
      all.length <= months ? all : all.sublist(all.length - months);
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  AdminRange _range = AdminRange.sixMonths;

  /// Card chrome plus the chart, which is the tallest of the row's
  /// contents. Shared with the chart so the two cannot drift apart.
  /// The left column stacks an accounts card over a stat card, which is
  /// the tallest thing in the row; the chart is sized from what is left so
  /// the three cards line up without anything being measured at layout
  /// time.
  static const double _rowHeight = 360;
  static const double _chartHeight = 250;

  /// The months the chosen range actually covers.
  String? _spanOf(AdminMetrics? metrics) {
    final series = _range.tailOf(metrics?.monthlySales ?? const []);
    if (series.isEmpty) return null;
    return '${series.first.label} — ${series.last.label}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final businesses = ref.watch(adminBusinessListControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final accountName = authState is AuthAuthenticated ? authState.account.name : null;

    final all = businesses.items;
    final active = all.where((b) => b.status == BusinessAccountStatus.active).length;
    final disabled = all.where((b) => b.status == BusinessAccountStatus.disabled).length;
    // Every non-business figure here is derived from the real demo records
    // (`admin_metrics.dart`), never seeded onto the business row — so each
    // card's number is the sum of the per-business numbers the card's own
    // overview screen lists. While the aggregate is still loading the cards
    // show '—' rather than a zero that would read as a real total.
    final metrics = ref.watch(adminMetricsProvider).asData?.value;
    String total(AdminMetric metric) => metrics == null ? '—' : metric.totalLabel(metrics);

    return PageScaffold(
      title: l10n.adminNavDashboard,
      titleWidget: _Greeting(name: accountName, fallback: l10n.adminNavDashboard),
      subtitle: l10n.demoDataNotice,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminDashboard,
      secondaryActions: [
        DateRangeChip<AdminRange>(
          key: const ValueKey('adminRangeChip'),
          options: [
            (value: AdminRange.threeMonths, label: l10n.adminRangeMonths(3)),
            (value: AdminRange.sixMonths, label: l10n.adminRangeMonths(6)),
            (value: AdminRange.twelveMonths, label: l10n.adminRangeMonths(12)),
          ],
          selected: _range,
          span: _spanOf(metrics),
          onChanged: (value) => setState(() => _range = value),
        ),
      ],
      // The reference's primary action creates a business. This console has
      // no create-business route — only edit — and a button that opens
      // nothing is worse than no button (§57's "not one control is a
      // no-op"). Refresh is the action this screen genuinely offers: the
      // figures are derived live and an admin watching them wants them
      // re-folded on demand.
      primaryAction: AppButton(
        key: const ValueKey('adminRefreshMetrics'),
        label: l10n.refresh,
        icon: Icons.refresh,
        onPressed: () async {
          ref.invalidate(adminMetricsProvider);
          ref.invalidate(adminRecentActivityProvider);
          await ref.read(adminBusinessListControllerProvider.notifier).reload();
          // Re-folding derived figures usually lands on the same numbers,
          // so without this the control looks broken even when it worked.
          if (context.mounted) AppToast.success(context, l10n.refreshed);
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          _OverviewRow(
            l10n: l10n,
            total: all.length,
            active: active,
            disabled: disabled,
            employees: total(AdminMetric.employees),
            metrics: metrics,
            range: _range,
            chartHeight: _chartHeight,
            rowHeight: _rowHeight,
          ),
          _TileRow(l10n: l10n, total: total),
          _BottomRow(l10n: l10n, businesses: all),
        ],
      ),
    );
  }
}

/// "Welcome Back, Admin" — the same two-tone greeting the business
/// dashboard uses, so the two areas open the same way.
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

/// The reference's leading row: the accounts panel with the people figure
/// beneath it, the platform sales chart, and a health card.
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.l10n,
    required this.total,
    required this.active,
    required this.disabled,
    required this.employees,
    required this.metrics,
    required this.range,
    required this.chartHeight,
    required this.rowHeight,
  });

  final AppLocalizations l10n;
  final int total;
  final int active;
  final int disabled;
  final String employees;
  final AdminMetrics? metrics;
  final AdminRange range;
  final double chartHeight;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final accounts = _AccountsCard(l10n: l10n, total: total, active: active, disabled: disabled);
    final people = _PeopleCard(l10n: l10n, value: employees);
    final chart = _PlatformSalesCard(l10n: l10n, metrics: metrics, range: range, height: chartHeight);
    final health = _AccountHealthCard(l10n: l10n, total: total, active: active, disabled: disabled);

    // Decided from the window, not measured with a `LayoutBuilder`: a
    // LayoutBuilder builds its subtree during layout, which is what tripped
    // Flutter's "built during layout" assertion on the web renderer when
    // this row first carried a chart.
    if (MediaQuery.sizeOf(context).width < 1180) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [accounts, people, chart, health],
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: accounts),
                const SizedBox(height: AppSpacing.lg),
                people,
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 5, child: chart),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 3, child: health),
        ],
      ),
    );
  }
}

/// The platform's headline: how many business accounts exist, on the brand
/// panel, with the status split as two pills that really filter the list
/// they summarize.
class _AccountsCard extends ConsumerWidget {
  const _AccountsCard({
    required this.l10n,
    required this.total,
    required this.active,
    required this.disabled,
  });

  final AppLocalizations l10n;
  final int total;
  final int active;
  final int disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: l10n.adminNavBusinesses,
      subtitle: l10n.adminAccountsOnPlatform,
      padding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        AppCircleButton(
          key: const ValueKey('adminOpenBusinesses'),
          icon: Icons.arrow_outward,
          tooltip: l10n.view,
          onPressed: () => openAdminBusinesses(context, ref),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandPanel(
            eyebrow: platformBrandName,
            label: l10n.adminTotalBusinesses,
            value: '$total',
            icon: Icons.shield_outlined,
            padding: const EdgeInsets.all(AppSpacing.lg),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatusFilterPill(
                  key: const ValueKey('adminFilterActive'),
                  label: l10n.statusActive,
                  count: active,
                  tone: StatusTone.success,
                  onTap: () => openAdminBusinesses(context, ref, status: BusinessAccountStatus.active),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatusFilterPill(
                  key: const ValueKey('adminFilterDisabled'),
                  label: l10n.statusDisabled,
                  count: disabled,
                  tone: StatusTone.danger,
                  onTap: () => openAdminBusinesses(context, ref, status: BusinessAccountStatus.disabled),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A dot, a count and a status word, as one tap target.
///
/// These replaced two stat cards. The count each shows is folded from the
/// same list the tap then opens filtered, so the figure on the pill and the
/// rows behind it can never be two different numbers.
class _StatusFilterPill extends StatelessWidget {
  const _StatusFilterPill({
    super.key,
    required this.label,
    required this.count,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final int count;
  final StatusTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = statusToneColors(context, tone);
    return Material(
      color: bg,
      borderRadius: AppRadius.pillRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  '$count $label',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The people figure under the accounts panel — the reference's "Total
/// Users" card. Still a [StatCard], so it drills into the same per-business
/// employee overview its number is folded from.
class _PeopleCard extends StatelessWidget {
  const _PeopleCard({required this.l10n, required this.value});

  final AppLocalizations l10n;
  final String value;

  @override
  Widget build(BuildContext context) {
    return StatCard(
      label: l10n.navEmployees,
      value: value,
      icon: AdminMetric.employees.icon,
      onTap: () => context.push(AdminMetric.employees.overviewRoute),
    );
  }
}

/// Platform sales over the last six months, switchable between revenue and
/// order count — the reference's "Platform Sales" card.
class _PlatformSalesCard extends StatefulWidget {
  const _PlatformSalesCard({
    required this.l10n,
    required this.metrics,
    required this.range,
    required this.height,
  });

  final AppLocalizations l10n;
  final AdminMetrics? metrics;
  final AdminRange range;
  final double height;

  @override
  State<_PlatformSalesCard> createState() => _PlatformSalesCardState();
}

enum _Series { orders, sales }

class _PlatformSalesCardState extends State<_PlatformSalesCard> {
  _Series _series = _Series.sales;
  int? _selected;

  @override
  void didUpdateWidget(_PlatformSalesCard old) {
    super.didUpdateWidget(old);
    if (old.range != widget.range) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final m = widget.metrics;
    final points = widget.range.tailOf(switch (_series) {
      _Series.sales => m?.monthlySales ?? const [],
      _Series.orders => m?.monthlyOrders ?? const [],
    });

    return SectionCard(
      title: _series == _Series.sales ? l10n.reportRevenue : l10n.navOrders,
      subtitle: l10n.adminAcrossAllBusinesses,
      padding: const EdgeInsets.all(AppSpacing.lg),
      actions: [
        AppSegmentedControl<_Series>(
          segments: [
            (value: _Series.orders, label: l10n.navOrders, key: const ValueKey('adminSeriesOrders')),
            (value: _Series.sales, label: l10n.navSales, key: const ValueKey('adminSeriesSales')),
          ],
          selected: _series,
          // The two series are different lengths of the same six months but
          // different magnitudes; keeping the highlighted index across a
          // switch would point at an unrelated bar.
          onChanged: (value) => setState(() {
            _series = value;
            _selected = null;
          }),
        ),
      ],
      child: VerticalBarChart(
        points: [for (final p in points) (label: p.label, value: p.value)],
        emptyLabel: l10n.dashboardNoChartData,
        height: widget.height,
        valueFormatter: (v) => v.toStringAsFixed(0),
        selectedIndex: _selected,
        onSelected: (i) => setState(() => _selected = i),
      ),
    );
  }
}

/// The health slot. Not API uptime — nothing measures that with the backend
/// off — but the platform-level health an admin can actually act on: how
/// much of the estate is active, and whether anything is disabled.
class _AccountHealthCard extends ConsumerWidget {
  const _AccountHealthCard({
    required this.l10n,
    required this.total,
    required this.active,
    required this.disabled,
  });

  final AppLocalizations l10n;
  final int total;
  final int active;
  final int disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final healthy = disabled == 0 && total > 0;
    final share = total == 0 ? 0.0 : active / total;

    return SectionCard(
      title: l10n.adminAccountHealth,
      subtitle: l10n.adminAccountsOnPlatform,
      icon: Icons.health_and_safety_outlined,
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
                  value: total == 0 ? '—' : '${(share * 100).toStringAsFixed(1)}%',
                  style: AppTypography.kpiValueLarge,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: StatusPill(
                  label: healthy ? l10n.adminHealthHealthy : l10n.adminHealthNeedsReview,
                  color: healthy ? colors.success : colors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // A proportion bar rather than a trend line: the figure above is
          // a share of a set, not a series over time, and a sparkline here
          // would imply history nothing recorded.
          ClipRRect(
            borderRadius: AppRadius.pillRadius,
            child: Row(
              children: [
                // `Expanded` asserts flex > 0, so an empty segment is left
                // out rather than given a zero share.
                if (active > 0)
                  Expanded(flex: active, child: Container(height: 10, color: colors.success)),
                if (active > 0 && disabled > 0) const SizedBox(width: 3),
                if (disabled > 0)
                  Expanded(flex: disabled, child: Container(height: 10, color: colors.error)),
                if (total == 0)
                  Expanded(child: Container(height: 10, color: colors.surfaceMuted)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$active / $total',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// The reference's tile row — the remaining record metrics, each drilling
/// into the per-business overview its number is folded from.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.l10n, required this.total});

  final AppLocalizations l10n;
  final String Function(AdminMetric) total;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100
        ? _tileMetrics.length
        : width > 700
            ? 2
            : 1;
    final cards = [
      for (final metric in _tileMetrics)
        StatCard(
          label: metric.label(l10n),
          value: total(metric),
          icon: metric.icon,
          onTap: () => context.push(metric.overviewRoute),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final card in cards) SizedBox(width: cellWidth, child: card)],
        );
      },
    );
  }
}

/// The closing row: the account table, and the platform's own activity
/// where the reference puts its backup card.
class _BottomRow extends ConsumerWidget {
  const _BottomRow({required this.l10n, required this.businesses});

  final AppLocalizations l10n;
  final List<AdminBusiness> businesses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final table = _BusinessesCard(l10n: l10n, businesses: businesses);
    final activity = _ActivityCard(l10n: l10n, businesses: businesses);

    if (MediaQuery.sizeOf(context).width < 1180) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [table, activity],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: table),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: activity),
      ],
    );
  }
}

class _BusinessesCard extends ConsumerWidget {
  const _BusinessesCard({required this.l10n, required this.businesses});

  final AppLocalizations l10n;
  final List<AdminBusiness> businesses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final metrics = ref.watch(adminMetricsProvider).asData?.value;

    return SectionCard(
      title: l10n.adminNavBusinesses,
      subtitle: l10n.adminSelectBusiness,
      icon: Icons.apartment_outlined,
      actions: [
        AppCircleButton(
          icon: Icons.arrow_outward,
          tooltip: l10n.view,
          onPressed: () => openAdminBusinesses(context, ref),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A header row, not a DataTable: five rows of summary inside a
          // card do not need a table's scrolling, sorting or selection
          // machinery, and the real Businesses screen already provides all
          // three.
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.sm, bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(l10n.fieldBusiness,
                      style: AppTypography.tableHeader.copyWith(color: colors.textMuted)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(l10n.fieldBusinessType,
                      style: AppTypography.tableHeader.copyWith(color: colors.textMuted)),
                ),
                Expanded(
                  child: Text(l10n.navEmployees,
                      textAlign: TextAlign.end,
                      style: AppTypography.tableHeader.copyWith(color: colors.textMuted)),
                ),
                Expanded(
                  child: Text(l10n.navProducts,
                      textAlign: TextAlign.end,
                      style: AppTypography.tableHeader.copyWith(color: colors.textMuted)),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 96,
                  child: Text(l10n.fieldStatus,
                      style: AppTypography.tableHeader.copyWith(color: colors.textMuted)),
                ),
              ],
            ),
          ),
          for (final b in businesses.take(5))
            _BusinessRow(business: b, l10n: l10n, metrics: metrics),
        ],
      ),
    );
  }
}

/// One business on the shortlist — avatar, name, its type as a neutral tag,
/// the two record counts an admin scans for, and account status.
class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.business, required this.l10n, required this.metrics});

  final AdminBusiness business;
  final AppLocalizations l10n;
  final AdminMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = business.status == BusinessAccountStatus.active;
    final row = metrics?.forBusiness(business.id);

    Widget count(int? value) => Text(
          value?.toString() ?? '—',
          textAlign: TextAlign.end,
          style: AppTypography.tableText.copyWith(color: colors.textPrimary),
        );

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.smRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.adminBusinessDetail(business.id)),
        hoverColor: colors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    AppAvatar(label: business.name),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            business.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                          ),
                          if (business.address != null)
                            Text(
                              business.address!,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(color: colors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppTag(label: business.businessType),
                ),
              ),
              Expanded(child: count(row?.employeeCount)),
              Expanded(child: count(row?.productCount)),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 96,
                // Explicit label rather than `StatusBadge.forStatus`: a
                // business account is "Disabled" in this product's
                // vocabulary, and the catalog's nearest entry reads
                // "Inactive" — close enough to look right and wrong enough
                // to teach the wrong word.
                child: StatusDot(
                  label: isActive ? l10n.statusActive : l10n.statusDisabled,
                  tone: isActive ? StatusTone.success : StatusTone.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform activity, and the accounts producing it.
class _ActivityCard extends ConsumerWidget {
  const _ActivityCard({required this.l10n, required this.businesses});

  final AppLocalizations l10n;
  final List<AdminBusiness> businesses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final activity = ref.watch(adminRecentActivityProvider).asData?.value ?? const [];

    return SectionCard(
      title: l10n.dashboardRecentActivity,
      subtitle: l10n.adminAcrossAllBusinesses,
      icon: Icons.history,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activity.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                l10n.dashboardNoActivityYet,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            )
          else
            for (final entry in activity.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 7),
                      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.description,
                            style: AppTypography.body.copyWith(color: colors.textPrimary),
                          ),
                          Text(
                            entry.businessName,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          if (businesses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.adminNavBusinesses,
                    style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.adminSelectBusiness,
                    style: AppTypography.cardSubtitle.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _AvatarCluster(businesses: businesses),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Overlapping account avatars with an overflow counter — the reference's
/// cluster, over the real account list.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.businesses});

  final List<AdminBusiness> businesses;

  static const int _max = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = businesses.take(_max).toList();
    final overflow = businesses.length - shown.length;

    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            PositionedDirectional(
              start: i * 24.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surfaceMuted, width: 2),
                ),
                child: AppAvatar(label: shown[i].name, size: 30),
              ),
            ),
          if (overflow > 0)
            PositionedDirectional(
              start: shown.length * 24.0,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surfaceMuted, width: 2),
                ),
                child: Text(
                  '+$overflow',
                  style: AppTypography.caption.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Businesses/Active/Disabled all open the same Businesses list their
/// numbers were folded from (`adminBusinessListControllerProvider`) — the
/// status ones additionally pre-apply the real filter the list already
/// supports (`admin_repository.dart` reads `query.filters['status']`), so
/// the count on the control and the rows the admin lands on come from the
/// exact same data, never a second hard-coded number.
///
/// These are the exception to the drill-down rule on purpose: a *business*
/// statistic's records ARE the business list, so there is no business left
/// to choose. `context.go`, not `push`: they stay inside the admin shell as
/// a peer navigation, like the header.
///
/// Employees/Products/Orders/Sales are records that belong to individual
/// tenants, so they `push` into the metric's overview (`/admin/<metric>`) —
/// the admin picks a business there, and only then sees that business's
/// records. They never open the business shell's own operational tables; a
/// System Admin session is redirected out of those (`app_router.dart`'s
/// redirect) precisely so a platform statistic can't drop anyone into a
/// warehouse's working screen.
void openAdminBusinesses(BuildContext context, WidgetRef ref, {BusinessAccountStatus? status}) {
  ref
      .read(adminBusinessListControllerProvider.notifier)
      .setFilters(status == null ? {} : {'status': status});
  context.go(AppRoutes.adminBusinesses);
}
