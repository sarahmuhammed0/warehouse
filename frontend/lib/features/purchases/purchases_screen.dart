import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import 'data/purchase_models.dart';
import 'data/purchase_providers.dart';

/// Purchases (spec §20).
class PurchasesPlaceholderScreen extends ConsumerWidget {
  const PurchasesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(purchaseListControllerProvider);
    final controller = ref.read(purchaseListControllerProvider.notifier);

    final columns = <AppTableColumn<Purchase>>[
      AppTableColumn(label: l10n.fieldPurchaseNumber, cellBuilder: (context, item) => Text(item.purchaseNumber)),
      AppTableColumn(label: l10n.fieldSupplier, cellBuilder: (context, item) => Text(item.supplierName)),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(item.createdAt.toString().split(' ').first)),
      AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.total.toStringAsFixed(2))),
      AppTableColumn(label: l10n.fieldRemainingAmount, numeric: true, cellBuilder: (context, item) => Text(item.remainingAmount.toStringAsFixed(2))),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: switch (item.status) { PurchaseStatus.pending => l10n.statusPending, PurchaseStatus.completed => l10n.statusCompleted, PurchaseStatus.cancelled => l10n.statusCancelled },
          tone: switch (item.status) { PurchaseStatus.pending => StatusTone.warning, PurchaseStatus.completed => StatusTone.success, PurchaseStatus.cancelled => StatusTone.danger },
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navPurchases,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navPurchases}', icon: Icons.add, onPressed: () => context.push(AppRoutes.purchaseNew)),
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Purchase>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            onRowTap: (item) => context.push(AppRoutes.purchaseDetail(item.id)),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage),
        ],
      ),
    );
  }
}
