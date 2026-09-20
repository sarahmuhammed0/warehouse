import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/dashboard/dashboard_cards.dart';
import '../../../shared/dashboard/metric_cards.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/feedback/confirm_dialog.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/admin_business_models.dart';
import '../data/admin_metrics.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';

/// System Admin business detail (spec §37) — profile, per-business stats,
/// recent activity, and platform-level controls (Disable/Activate here;
/// Reset password/Manage users/View reports are stubbed as clearly-labeled
/// controls since they need backend endpoints this phase doesn't add —
/// see `docs/frontend-backend-contract-notes.md`).
class AdminBusinessDetailScreen extends ConsumerWidget {
  const AdminBusinessDetailScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessByIdProvider(businessId));
    final metrics = ref.watch(adminMetricsProvider).asData?.value;

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.adminBusinesses,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.adminBusinesses,
        body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessByIdProvider(businessId))),
      ),
      data: (business) => PageScaffold(
        title: business.name,
        showBackButton: true,
        backFallbackRoute: AppRoutes.adminBusinesses,
        secondaryActions: [
          if (business.status == BusinessAccountStatus.active)
            AppButton(
              label: l10n.deactivate,
              variant: AppButtonVariant.destructive,
              onPressed: () async {
                final confirmed = await confirmAction(context, title: l10n.deleteConfirmTitle, description: business.name, confirmLabel: l10n.deactivate, cancelLabel: l10n.cancel, isDestructive: true);
                if (confirmed ?? false) {
                  await ref.read(adminBusinessListControllerProvider.notifier).setStatus(business.id, BusinessAccountStatus.disabled);
                  ref.invalidate(adminBusinessByIdProvider(business.id));
                }
              },
            )
          else
            AppButton(
              label: l10n.activate,
              onPressed: () async {
                await ref.read(adminBusinessListControllerProvider.notifier).setStatus(business.id, BusinessAccountStatus.active);
                ref.invalidate(adminBusinessByIdProvider(business.id));
              },
            ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  _row(l10n.fieldModule, business.businessType),
                  _row(l10n.fieldPhone, business.phone),
                  if (business.email != null) _row(l10n.fieldEmail, business.email!),
                  if (business.address != null) _row(l10n.fieldAddress, business.address!),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: business.status == BusinessAccountStatus.active ? l10n.statusActive : l10n.statusDisabled,
                        tone: business.status == BusinessAccountStatus.active ? StatusTone.success : StatusTone.danger,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // The same derived numbers the drill-down shows, and the same
            // destination: a business is already chosen here, so each card
            // opens that business's records directly (drill-down level 3) —
            // no second business-selection step, and still never the
            // business app's own operational table.
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final metric in AdminMetric.values)
                  SizedBox(
                    width: 200,
                    child: StatCard(
                      label: metric.label(l10n),
                      value: metrics == null
                          ? '—'
                          : metric == AdminMetric.sales
                              ? metrics.forBusiness(business.id).salesTotal.toStringAsFixed(0)
                              : '${metric.countFor(metrics.forBusiness(business.id))}',
                      icon: metric.icon,
                      onTap: () => context.push(metric.recordsRoute(business.id)),
                    ),
                  ),
              ],
            ),
            SectionCard(
              title: l10n.fieldPermission,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(label: l10n.edit, icon: Icons.edit_outlined, variant: AppButtonVariant.outline, onPressed: () {}),
                  AppButton(label: l10n.navEmployees, icon: Icons.people_outline, variant: AppButtonVariant.outline, onPressed: () {}),
                  AppButton(label: l10n.navReports, icon: Icons.bar_chart_outlined, variant: AppButtonVariant.outline, onPressed: () {}),
                  AppButton(label: l10n.password, icon: Icons.lock_reset_outlined, variant: AppButtonVariant.outline, onPressed: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(children: [Expanded(child: Text(label, style: AppTypography.label)), Expanded(child: Text(value, style: AppTypography.bodyStrong))]);
  }
}
