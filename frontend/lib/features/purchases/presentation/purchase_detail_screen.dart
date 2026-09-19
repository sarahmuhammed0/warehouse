import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/breadcrumbs.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/purchase_models.dart';
import '../data/purchase_providers.dart';

class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});
  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(purchaseByIdProvider(purchaseId));

    return async.when(
      loading: () => PageScaffold(title: l10n.details, body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
      error: (_, _) => PageScaffold(title: l10n.details, body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(purchaseByIdProvider(purchaseId)))),
      data: (purchase) => PageScaffold(
        title: purchase.purchaseNumber,
        breadcrumbs: [BreadcrumbItem(l10n.navPurchases, onTap: () => context.go(AppRoutes.purchases)), BreadcrumbItem(purchase.purchaseNumber)],
        secondaryActions: [
          if (purchase.status == PurchaseStatus.pending) ...[
            AppButton(
              label: l10n.statusCompleted,
              onPressed: () async {
                await ref.read(purchaseListControllerProvider.notifier).updateStatus(purchase.id, PurchaseStatus.completed);
                ref.invalidate(purchaseByIdProvider(purchase.id));
              },
            ),
            AppButton(
              label: l10n.cancelAction,
              variant: AppButtonVariant.destructive,
              onPressed: () async {
                await ref.read(purchaseListControllerProvider.notifier).updateStatus(purchase.id, PurchaseStatus.cancelled);
                ref.invalidate(purchaseByIdProvider(purchase.id));
              },
            ),
          ],
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AppCard(
              title: Text(l10n.fieldProduct),
              child: Column(
                children: [
                  for (final item in purchase.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(item.productName)),
                          Expanded(child: Text('×${item.quantity}', textAlign: TextAlign.center)),
                          Expanded(child: Text(item.unitCost.toStringAsFixed(2), textAlign: TextAlign.end)),
                          Expanded(child: Text(item.lineTotal.toStringAsFixed(2), textAlign: TextAlign.end, style: AppTypography.bodyStrong)),
                        ],
                      ),
                    ),
                  const Divider(),
                  _row(l10n.fieldGrandTotal, purchase.total.toStringAsFixed(2), strong: true),
                  _row(l10n.fieldPaidAmount, purchase.paidAmount.toStringAsFixed(2)),
                  _row(l10n.fieldRemainingAmount, purchase.remainingAmount.toStringAsFixed(2)),
                ],
              ),
            ),
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  _row(l10n.fieldSupplier, purchase.supplierName),
                  _row(l10n.fieldPaymentMethod, purchase.paymentMethod),
                  _row(l10n.fieldCreatedBy, purchase.createdBy),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: switch (purchase.status) { PurchaseStatus.pending => l10n.statusPending, PurchaseStatus.completed => l10n.statusCompleted, PurchaseStatus.cancelled => l10n.statusCancelled },
                        tone: switch (purchase.status) { PurchaseStatus.pending => StatusTone.warning, PurchaseStatus.completed => StatusTone.success, PurchaseStatus.cancelled => StatusTone.danger },
                      ),
                    ],
                  ),
                  if (purchase.status == PurchaseStatus.completed) Text(l10n.demoDataNotice, style: AppTypography.helperText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) {
    final style = strong ? AppTypography.sectionTitle : AppTypography.body;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: strong ? style : AppTypography.label), Text(value, style: style)]);
  }
}
