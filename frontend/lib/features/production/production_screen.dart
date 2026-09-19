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
import 'data/production_models.dart';
import 'data/production_providers.dart';

/// Production (spec §21/§22) — optional module, only relevant to
/// manufacturing business types (see `docs/frontend-coverage.md`'s note on
/// business-type-driven module visibility).
class ProductionPlaceholderScreen extends ConsumerWidget {
  const ProductionPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(productionListControllerProvider);
    final controller = ref.read(productionListControllerProvider.notifier);

    final columns = <AppTableColumn<ProductionOrder>>[
      AppTableColumn(label: l10n.fieldProductionNumber, cellBuilder: (context, item) => Text(item.productionNumber)),
      AppTableColumn(label: l10n.fieldProduct, cellBuilder: (context, item) => Text(item.productName)),
      AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.quantityProduced}/${item.quantityPlanned}')),
      AppTableColumn(label: l10n.fieldEmployee, cellBuilder: (context, item) => Text(item.assignedTo ?? '—')),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: switch (item.status) { ProductionStatus.planned => l10n.statusPlanned, ProductionStatus.inProgress => l10n.statusInProgress, ProductionStatus.completed => l10n.statusCompleted, ProductionStatus.cancelled => l10n.statusCancelled },
          tone: switch (item.status) { ProductionStatus.planned => StatusTone.neutral, ProductionStatus.inProgress => StatusTone.info, ProductionStatus.completed => StatusTone.success, ProductionStatus.cancelled => StatusTone.danger },
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navProduction,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navProduction}', icon: Icons.add, onPressed: () => context.push(AppRoutes.productionNew)),
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<ProductionOrder>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            onRowTap: (item) => context.push(AppRoutes.productionDetail(item.id)),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage),
        ],
      ),
    );
  }
}
