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
import '../../../shared/layout/breadcrumbs.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/admin_business_models.dart';
import '../data/admin_providers.dart';

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

    return async.when(
      loading: () => PageScaffold(title: l10n.details, body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
      error: (_, _) => PageScaffold(title: l10n.details, body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessByIdProvider(businessId)))),
      data: (business) => PageScaffold(
        title: business.name,
        breadcrumbs: [BreadcrumbItem(l10n.adminNavBusinesses, onTap: () => context.go(AppRoutes.adminBusinesses)), BreadcrumbItem(business.name)],
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
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(width: 200, child: StatCard(label: l10n.navProducts, value: '${business.productCount}', icon: Icons.inventory_2_outlined)),
                SizedBox(width: 200, child: StatCard(label: l10n.navOrders, value: '${business.orderCount}', icon: Icons.receipt_long_outlined)),
                SizedBox(width: 200, child: StatCard(label: l10n.navSales, value: business.salesTotal.toStringAsFixed(0), icon: Icons.point_of_sale_outlined)),
                SizedBox(width: 200, child: StatCard(label: l10n.fieldEmployee, value: '${business.userCount}', icon: Icons.people_outline)),
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
