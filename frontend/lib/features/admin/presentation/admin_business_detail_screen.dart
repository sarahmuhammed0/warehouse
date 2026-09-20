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
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/feedback/confirm_dialog.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/admin_business_models.dart';
import '../data/admin_metrics.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';
import 'admin_reset_password_dialog.dart';

/// System Admin business detail (spec §57) — business profile, per-business
/// statistics, and the six platform controls §57 lists: Edit, Disable,
/// Activate, Reset password, Manage users, View reports.
///
/// Every one of them does something real. The PDF lists the six by name and
/// says nothing whatsoever about what each should do when clicked, so the
/// behaviours below are this frontend's interpretation — documented in
/// `docs/frontend-coverage.md` as interpretation rather than passed off as
/// spec. Where a control cannot be truthfully completed without a backend
/// (Reset password — the demo auth layer stores no passwords), it performs
/// a real local action and says on screen exactly what it did.
class AdminBusinessDetailScreen extends ConsumerWidget {
  const AdminBusinessDetailScreen({super.key, required this.businessId});
  final String businessId;

  /// Disable and Activate are the same control wearing two faces, so they
  /// share one implementation: confirm (naming the business), write, toast.
  /// §3 of this task is explicit that only the action matching the CURRENT
  /// status may be offered — hence one button, chosen by status, never two.
  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    AdminBusiness business,
    BusinessAccountStatus target,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final disabling = target == BusinessAccountStatus.disabled;
    final confirmed = await confirmAction(
      context,
      title: disabling ? l10n.adminDisableBusinessTitle(business.name) : l10n.adminActivateBusinessTitle(business.name),
      description: disabling ? l10n.adminDisableBusinessDescription : l10n.adminActivateBusinessDescription,
      confirmLabel: disabling ? l10n.deactivate : l10n.activate,
      cancelLabel: l10n.cancel,
      isDestructive: disabling,
    );
    if (!(confirmed ?? false)) return;
    await ref.read(adminBusinessListControllerProvider.notifier).setStatus(business.id, target);
    if (!context.mounted) return;
    AppToast.success(
      context,
      disabling ? l10n.adminBusinessDisabled(business.name) : l10n.adminBusinessActivated(business.name),
    );
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, AdminBusiness business) async {
    final l10n = AppLocalizations.of(context)!;
    final done = await showAdminResetPasswordDialog(context, business: business);
    if (!(done ?? false) || !context.mounted) return;
    AppToast.success(context, l10n.adminPasswordResetRecorded(business.name));
  }

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
          // Exactly one status action, matching the current status.
          if (business.status == BusinessAccountStatus.active)
            AppButton(
              key: const ValueKey('adminDisableBusiness'),
              label: l10n.deactivate,
              icon: Icons.block_outlined,
              variant: AppButtonVariant.destructive,
              onPressed: () => _setStatus(context, ref, business, BusinessAccountStatus.disabled),
            )
          else
            AppButton(
              key: const ValueKey('adminActivateBusiness'),
              label: l10n.activate,
              icon: Icons.check_circle_outline,
              onPressed: () => _setStatus(context, ref, business, BusinessAccountStatus.active),
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
                  // §57's "Business profile" block: Name (the page title),
                  // Type, Address, Phone, Email, Status. Logo is omitted —
                  // nothing populates `logoUrl` yet, and an empty avatar
                  // would imply an upload feature that doesn't exist.
                  _row(l10n.fieldBusinessType, business.businessType),
                  _row(l10n.fieldPhone, business.phone),
                  if (business.email != null) _row(l10n.fieldEmail, business.email!),
                  if (business.address != null) _row(l10n.fieldAddress, business.address!),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: StatusBadge(
                            label: business.status == BusinessAccountStatus.active ? l10n.statusActive : l10n.statusDisabled,
                            tone: business.status == BusinessAccountStatus.active ? StatusTone.success : StatusTone.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Shown only once a reset has actually happened — this is
                  // the observable result of the Reset password control, and
                  // the reason it isn't a no-op dressed up with a toast.
                  if (business.lastPasswordResetAt != null)
                    _row(l10n.adminLastPasswordReset, _formatDate(business.lastPasswordResetAt!)),
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
            // §57 calls this block "Controls", not "Permission" — these are
            // platform actions on a business account. Role/permission
            // editing is a different thing entirely and lives in the
            // Users/Roles area (§23/§24).
            SectionCard(
              title: l10n.adminControls,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Every control below acts on `business` — the record this
                  // screen loaded by its own route parameter — so none of
                  // them can operate on a different tenant than the one on
                  // screen.
                  AppButton(
                    key: const ValueKey('adminEditBusiness'),
                    label: l10n.edit,
                    icon: Icons.edit_outlined,
                    variant: AppButtonVariant.outline,
                    onPressed: () => context.push(AppRoutes.adminBusinessEdit(business.id)),
                  ),
                  AppButton(
                    key: const ValueKey('adminResetPassword'),
                    label: l10n.adminResetPasswordTitle,
                    icon: Icons.lock_reset_outlined,
                    variant: AppButtonVariant.outline,
                    onPressed: () => _resetPassword(context, ref, business),
                  ),
                  // §57's "Manage users" — the drill-down's own per-business
                  // Employees level, so there is one screen for "this
                  // business's users" rather than two that could disagree.
                  AppButton(
                    key: const ValueKey('adminManageUsers'),
                    label: l10n.adminManageUsers,
                    icon: Icons.people_outline,
                    variant: AppButtonVariant.outline,
                    onPressed: () => context.push(AdminMetric.employees.recordsRoute(business.id)),
                  ),
                  AppButton(
                    key: const ValueKey('adminViewReports'),
                    label: l10n.navReports,
                    icon: Icons.bar_chart_outlined,
                    variant: AppButtonVariant.outline,
                    onPressed: () => context.push(AppRoutes.adminBusinessReports(business.id)),
                  ),
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

String _formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
