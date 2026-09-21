import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/paged_query.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/tables/app_data_table.dart';
import '../../../shared/tables/table_column.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_providers.dart';
import '../data/product_providers.dart';

/// One product's stock history (§8's "History" row action, §12's movement
/// ledger).
///
/// `LocalInventoryRepository.listMovements` has always supported a
/// `productId` filter and nothing ever passed one — the Products list had
/// no History action and the product detail screen's "Order history" card
/// rendered a permanent empty state. Now that sales, purchases, returns and
/// production all write movements, this is a real audit trail for a single
/// product rather than a list of manual adjustments.
final productMovementsProvider = FutureProvider.autoDispose.family<List<StockMovement>, String>((ref, productId) async {
  final result = await ref.watch(inventoryRepositoryProvider).listMovements(
        PagedQuery(pageSize: 200, filters: {'productId': productId}),
      );
  return result.items;
});

class ProductHistoryScreen extends ConsumerWidget {
  const ProductHistoryScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final product = ref.watch(productByIdProvider(productId)).asData?.value;
    final async = ref.watch(productMovementsProvider(productId));

    return PageScaffold(
      title: product?.name ?? l10n.reportStockMovement,
      subtitle: product == null ? null : l10n.reportStockMovement,
      showBackButton: true,
      backFallbackRoute: AppRoutes.productDetail(productId),
      body: async.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        error: (_, _) => AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(productMovementsProvider(productId))),
        data: (movements) => AppDataTable<StockMovement>(
          columns: [
            AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, m) => Text(_date(m.dateTime))),
            AppTableColumn(label: l10n.fieldModule, cellBuilder: (c, m) => Text(m.type.name)),
            AppTableColumn(
              label: l10n.fieldQuantity,
              numeric: true,
              cellBuilder: (c, m) => Text('${m.previousQuantity} → ${m.newQuantity}'),
            ),
            AppTableColumn(label: l10n.fieldReason, cellBuilder: (c, m) => Text(m.note ?? '—')),
            AppTableColumn(label: l10n.fieldCreatedBy, cellBuilder: (c, m) => Text(m.userName)),
          ],
          rows: movements,
          idOf: (m) => m.id,
          emptyTitle: l10n.emptyStateDefaultTitle,
          emptyDescription: l10n.emptyStateDefaultDescription,
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
