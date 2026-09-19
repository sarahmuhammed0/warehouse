import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/dashboard/metric_cards.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/breadcrumbs.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/customer_models.dart';
import '../data/customer_providers.dart';
import 'customer_form_dialog.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(customerByIdProvider(customerId));

    return async.when(
      loading: () => PageScaffold(title: l10n.details, body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
      error: (_, _) => PageScaffold(title: l10n.details, body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(customerByIdProvider(customerId)))),
      data: (customer) => PageScaffold(
        title: customer.fullName,
        breadcrumbs: [
          BreadcrumbItem(l10n.navCustomers, onTap: () => context.go(AppRoutes.customers)),
          BreadcrumbItem(customer.fullName),
        ],
        primaryAction: AppButton(label: l10n.edit, icon: Icons.edit_outlined, onPressed: () => showCustomerFormDialog(context, editing: customer)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(width: 220, child: StatCard(label: l10n.fieldTotalPurchases, value: customer.totalPurchases.toStringAsFixed(2), icon: Icons.payments_outlined)),
                SizedBox(width: 220, child: StatCard(label: l10n.fieldOutstandingBalance, value: customer.outstandingBalance.toStringAsFixed(2), icon: Icons.account_balance_wallet_outlined)),
                SizedBox(width: 220, child: StatCard(label: l10n.navOrders, value: '${customer.orderCount}', icon: Icons.receipt_long_outlined)),
              ],
            ),
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  _row(context, l10n.fieldCode, customer.code),
                  _row(context, l10n.fieldPhone, customer.phone),
                  if (customer.secondaryPhone != null) _row(context, l10n.fieldSecondaryPhone, customer.secondaryPhone!),
                  if (customer.email != null) _row(context, l10n.fieldEmail, customer.email!),
                  if (customer.company != null) _row(context, l10n.fieldCompany, customer.company!),
                  if (customer.address != null) _row(context, l10n.fieldAddress, customer.address!),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: customer.status == CustomerStatus.active ? l10n.statusActive : l10n.statusInactive,
                        tone: customer.status == CustomerStatus.active ? StatusTone.success : StatusTone.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppCard(
              title: Text(l10n.fieldOrderHistory),
              child: AppEmptyState(icon: Icons.receipt_long_outlined, title: l10n.emptyStateDefaultTitle, description: l10n.demoDataNotice),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.label)),
        Expanded(child: Text(value, style: AppTypography.bodyStrong)),
      ],
    );
  }
}
