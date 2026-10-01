import '../../../core/config/data_source_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/dashboard/metric_cards.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/supplier_models.dart';
import '../data/supplier_providers.dart';
import 'supplier_form_dialog.dart';

class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});
  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(supplierByIdProvider(supplierId));

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.suppliers,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.suppliers,
        body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(supplierByIdProvider(supplierId))),
      ),
      data: (supplier) => PageScaffold(
        title: supplier.name,
        showBackButton: true,
        backFallbackRoute: AppRoutes.suppliers,
        primaryAction: AppButton(label: l10n.edit, icon: Icons.edit_outlined, onPressed: () => showSupplierFormDialog(context, editing: supplier)),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(width: 220, child: StatCard(label: l10n.fieldTotalPurchases, value: supplier.totalPurchaseCost.toStringAsFixed(2), icon: Icons.payments_outlined)),
                SizedBox(width: 220, child: StatCard(label: l10n.fieldOutstandingBalance, value: supplier.outstandingBalance.toStringAsFixed(2), icon: Icons.account_balance_wallet_outlined)),
                SizedBox(width: 220, child: StatCard(label: l10n.navPurchases, value: '${supplier.purchaseCount}', icon: Icons.shopping_cart_outlined)),
              ],
            ),
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  _row(l10n.fieldPhone, supplier.phone),
                  if (supplier.email != null) _row(l10n.fieldEmail, supplier.email!),
                  if (supplier.contactPerson != null) _row(l10n.fieldContactPerson, supplier.contactPerson!),
                  if (supplier.address != null) _row(l10n.fieldAddress, supplier.address!),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: supplier.status == SupplierStatus.active ? l10n.statusActive : l10n.statusInactive,
                        tone: supplier.status == SupplierStatus.active ? StatusTone.success : StatusTone.neutral,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppCard(
              title: Text(l10n.fieldPurchaseHistory),
              child: AppEmptyState(icon: Icons.shopping_cart_outlined, title: l10n.emptyStateDefaultTitle, description: dataSourceNotice(l10n)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.label)),
        Expanded(child: Text(value, style: AppTypography.bodyStrong)),
      ],
    );
  }
}
