import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../inventory/data/inventory_models.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../inventory/data/stock_engine.dart';
import '../../../theme/app_typography.dart';
import '../data/return_models.dart';
import '../data/return_providers.dart';

/// Return detail — Requested → Approved/Rejected → Completed (§16). Inventory
/// only restocks on Completed (two-stage policy, see `ProductReturn.restocksOnCompletion`'s
/// doc comment and `docs/architecture.md`'s ambiguity #2).
class ReturnDetailScreen extends ConsumerWidget {
  const ReturnDetailScreen({super.key, required this.returnId});
  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(returnByIdProvider(returnId));

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.returns,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.returns,
        body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(returnByIdProvider(returnId))),
      ),
      data: (item) => PageScaffold(
        title: item.returnNumber,
        showBackButton: true,
        backFallbackRoute: AppRoutes.returns,
        secondaryActions: [
          if (item.status == ReturnStatus.requested) ...[
            AppButton(label: l10n.approve, onPressed: () => _update(context, ref, item, ReturnStatus.approved)),
            AppButton(label: l10n.reject, variant: AppButtonVariant.destructive, onPressed: () => _update(context, ref, item, ReturnStatus.rejected)),
          ],
          if (item.status == ReturnStatus.approved)
            AppButton(label: l10n.statusCompleted, onPressed: () => _update(context, ref, item, ReturnStatus.completed)),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AppCard(
              title: Text(l10n.fieldProduct),
              child: Column(
                children: [
                  for (final line in item.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(line.productName)),
                          Expanded(child: Text('×${line.quantity}', textAlign: TextAlign.center)),
                          Expanded(
                            child: StatusBadge(
                              label: line.condition == ItemCondition.sellable ? l10n.statusActive : l10n.statusRejected,
                              tone: line.condition == ItemCondition.sellable ? StatusTone.success : StatusTone.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            AppCard(
              title: Text(l10n.details),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  _row(l10n.fieldOrderNumber, item.orderNumber),
                  _row(l10n.fieldCustomer, item.customerName ?? '—'),
                  _row(l10n.fieldReason, item.reason),
                  _row(l10n.fieldRemainingAmount, item.refundAmount.toStringAsFixed(2)),
                  _row(l10n.fieldCreatedBy, item.requestedBy),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: switch (item.status) {
                          ReturnStatus.requested => l10n.statusRequested,
                          ReturnStatus.approved => l10n.statusApproved,
                          ReturnStatus.rejected => l10n.statusRejected,
                          ReturnStatus.completed => l10n.statusCompleted,
                        },
                        tone: switch (item.status) {
                          ReturnStatus.requested => StatusTone.neutral,
                          ReturnStatus.approved => StatusTone.info,
                          ReturnStatus.rejected => StatusTone.danger,
                          ReturnStatus.completed => StatusTone.success,
                        },
                      ),
                    ],
                  ),
                  if (item.notes != null) ...[const Divider(), Text(item.notes!)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, ProductReturn item, ReturnStatus status) async {
    await ref.read(returnListControllerProvider.notifier).updateStatus(item.id, status);
    ref.invalidate(returnByIdProvider(item.id));
    if (status != ReturnStatus.completed || !item.restocksOnCompletion) return;

    // The two-stage policy `ProductReturn.restocksOnCompletion` documents:
    // goods come back into stock when the return COMPLETES, not when it is
    // approved. Until now that getter had no call site and the
    // Sellable/Damaged dropdown had no consequence — both conditions
    // behaved identically. Now only sellable lines restock; damaged ones
    // still record a movement, because a damaged return is a real event
    // that a stock ledger should show.
    final engine = ref.read(stockEngineProvider);
    await engine.apply(
      [
        for (final line in item.items)
          StockChange(
            productId: line.productId,
            productName: line.productName,
            delta: line.condition == ItemCondition.sellable ? line.quantity : 0,
          ),
      ],
      type: MovementType.returnMovement,
      note: item.returnNumber,
    );

    // Close the loop back to the order. Without this a completed return
    // left its order still reading "Completed", so the two modules
    // disagreed about whether the goods had come back. Partial when only
    // some lines came back, fully Returned when all of them did.
    try {
      final order = await ref.read(orderRepositoryProvider).getById(item.orderId);
      final returnedByProduct = <String, int>{};
      for (final line in item.items) {
        returnedByProduct.update(line.productId, (v) => v + line.quantity, ifAbsent: () => line.quantity);
      }
      final everythingCameBack = order.items.every((o) => (returnedByProduct[o.productId] ?? 0) >= o.quantity);
      await ref.read(orderListControllerProvider.notifier).updateStatus(
            order.id,
            everythingCameBack ? OrderStatus.returned : OrderStatus.partiallyReturned,
          );
      ref.invalidate(orderByIdProvider(order.id));
    } catch (_) {
      // A return whose order no longer exists must not fail the return.
    }
  }

  Widget _row(String label, String value) {
    return Row(children: [Expanded(child: Text(label, style: AppTypography.label)), Expanded(child: Text(value, style: AppTypography.bodyStrong))]);
  }
}
