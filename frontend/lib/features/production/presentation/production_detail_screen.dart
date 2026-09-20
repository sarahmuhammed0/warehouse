import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../data/production_models.dart';
import '../data/production_providers.dart';

/// Production order detail — Planned → In Progress → Completed/Cancelled
/// (§22). Completion note communicates the eventual backend effect
/// (materials decrease, finished goods increase) without pretending it
/// already happened (§48: no fake production behavior).
class ProductionDetailScreen extends ConsumerWidget {
  const ProductionDetailScreen({super.key, required this.productionId});
  final String productionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(productionByIdProvider(productionId));

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.production,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.production,
        body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(productionByIdProvider(productionId))),
      ),
      data: (order) => PageScaffold(
        title: order.productionNumber,
        showBackButton: true,
        backFallbackRoute: AppRoutes.production,
        secondaryActions: [
          if (order.status == ProductionStatus.planned) ...[
            AppButton(label: l10n.statusInProgress, onPressed: () => _update(context, ref, order.id, ProductionStatus.inProgress)),
            AppButton(label: l10n.cancelAction, variant: AppButtonVariant.destructive, onPressed: () => _update(context, ref, order.id, ProductionStatus.cancelled)),
          ],
          if (order.status == ProductionStatus.inProgress)
            AppButton(label: l10n.statusCompleted, onPressed: () => _update(context, ref, order.id, ProductionStatus.completed)),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AppCard(
              title: Text('${l10n.navProduction} — Bill of Materials'),
              child: Column(
                children: [
                  for (final m in order.materials)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [Expanded(child: Text(m.materialProductName)), Text('${m.quantityRequired} ${m.unit}', style: AppTypography.bodyStrong)]),
                    ),
                  if (order.status == ProductionStatus.completed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l10n.demoDataNotice, style: AppTypography.helperText),
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
                  _row(l10n.fieldProduct, order.productName),
                  _row(l10n.fieldQuantity, '${order.quantityProduced}/${order.quantityPlanned}'),
                  if (order.batchNumber != null) _row(l10n.fieldBatchNumber, order.batchNumber!),
                  if (order.assignedTo != null) _row(l10n.fieldEmployee, order.assignedTo!),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                      StatusBadge(
                        label: switch (order.status) { ProductionStatus.planned => l10n.statusPlanned, ProductionStatus.inProgress => l10n.statusInProgress, ProductionStatus.completed => l10n.statusCompleted, ProductionStatus.cancelled => l10n.statusCancelled },
                        tone: switch (order.status) { ProductionStatus.planned => StatusTone.neutral, ProductionStatus.inProgress => StatusTone.info, ProductionStatus.completed => StatusTone.success, ProductionStatus.cancelled => StatusTone.danger },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref, String id, ProductionStatus status) async {
    await ref.read(productionListControllerProvider.notifier).updateStatus(id, status);
    ref.invalidate(productionByIdProvider(id));
  }

  Widget _row(String label, String value) {
    return Row(children: [Expanded(child: Text(label, style: AppTypography.label)), Expanded(child: Text(value, style: AppTypography.bodyStrong))]);
  }
}
