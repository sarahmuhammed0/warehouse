import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/cards/app_icon_chip.dart';
import '../../shared/cards/brand_panel.dart';
import '../../shared/dashboard/dashboard_cards.dart';
import '../../shared/dashboard/metric_cards.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'data/admin_business_models.dart';
import 'data/admin_metrics.dart';
import 'data/admin_providers.dart';
import 'presentation/admin_metric.dart';

/// The three cards on the second row. Employees sits on the first row next
/// to the business-account cards (it's a people statistic, not an
/// operational one) but drills down identically.
const _drilldownMetrics = [AdminMetric.products, AdminMetric.orders, AdminMetric.sales];

/// System Admin dashboard (spec §2/§36) — cross-tenant aggregate stats.
///
/// Shares the business dashboard's design system exactly — same cards,
/// same pills, same typography, same brand panel — but says what it is.
/// The panel is a platform panel (account counts, a shield), the figures
/// are cross-tenant, and nothing here opens a single business's operational
/// screens (§10: "System Admin is GLOBAL, business UI is BUSINESS-SPECIFIC;
/// do not mix the two").
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
          // The platform's own headline. A shield, not a business initial:
          // this shell administers every tenant and belongs to none.
          BrandPanel(
            eyebrow: l10n.appName,
            label: l10n.adminNavBusinesses,
            value: '${all.length}',
            icon: Icons.shield_outlined,
            // A full-width band, so the account counts sit beside the
            // headline rather than under it.
            wide: MediaQuery.sizeOf(context).width >= 1180,
            stats: [
              (label: l10n.statusActive, value: '$active'),
              (label: l10n.statusDisabled, value: '$disabled'),
            ],
          ),
          _AdminStatGrid(
            cards: [
              StatCard(
                label: l10n.adminNavBusinesses,
                value: '${all.length}',
                icon: Icons.apartment_outlined,
                onTap: () => _openBusinesses(context, ref),
              ),
              StatCard(
                label: l10n.statusActive,
                value: '$active',
                icon: Icons.check_circle_outline,
                tone: context.colors.success,
                onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.active),
              ),
              StatCard(
                label: l10n.statusDisabled,
                value: '$disabled',
                icon: Icons.block_outlined,
                tone: context.colors.error,
                onTap: () => _openBusinesses(context, ref, status: BusinessAccountStatus.disabled),
              ),
              StatCard(
                label: l10n.navEmployees,
                value: total(AdminMetric.employees),
                icon: AdminMetric.employees.icon,
                onTap: () => context.push(AdminMetric.employees.overviewRoute),
              ),
            ],
          ),
          _AdminStatGrid(
            cards: [
              for (final metric in _drilldownMetrics)
                StatCard(
                  label: metric.label(l10n),
                  value: total(metric),
                  icon: metric.icon,
                  onTap: () => context.push(metric.overviewRoute),
                ),
            ],
          ),
          ActivityListCard(
            title: l10n.dashboardRecentActivity,
            entries: [
              for (final entry in activity.asData?.value ?? const [])
                ActivityListEntry(
                  title: '${entry.businessName}: ${entry.description}',
                  timestamp: '',
                  icon: Icons.circle,
                ),
            ],
            emptyLabel: l10n.dashboardNoActivityYet,
          ),
          SectionCard(
            title: l10n.adminNavBusinesses,
            icon: Icons.apartment_outlined,
            actions: [
              AppCircleButton(
                icon: Icons.arrow_outward,
                tooltip: l10n.view,
                onPressed: () => _openBusinesses(context, ref),
              ),
            ],
            child: Column(
              children: [
                for (final b in all.take(5)) _BusinessRow(business: b, l10n: l10n),
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
    ref
        .read(adminBusinessListControllerProvider.notifier)
        .setFilters(status == null ? {} : {'status': status});
    context.go(AppRoutes.adminBusinesses);
  }
}

/// Four-up on a desktop, two-up on a tablet, stacked on a phone — the same
/// reflow rule the business dashboard's grid uses, so a card is the same
/// size on both sides of the product at the same width.
class _AdminStatGrid extends StatelessWidget {
  const _AdminStatGrid({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100
            ? (cards.length < 4 ? cards.length : 4)
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

/// One business on the dashboard's shortlist — avatar, name, its type as a
/// neutral tag, and its account status. A `ListTile` would have given three
/// of those four nowhere to go.
class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.business, required this.l10n});

  final AdminBusiness business;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = business.status == BusinessAccountStatus.active;

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
              AppAvatar(label: business.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  business.name,
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(child: AppTag(label: business.businessType)),
              const SizedBox(width: AppSpacing.md),
              // Explicit label rather than `StatusBadge.forStatus`: a
              // business account is "Disabled" in this product's
              // vocabulary, and the catalog's nearest entry reads
              // "Inactive" — close enough to look right and wrong enough
              // to teach the wrong word.
              StatusBadge(
                label: isActive ? l10n.statusActive : l10n.statusDisabled,
                tone: isActive ? StatusTone.success : StatusTone.danger,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
