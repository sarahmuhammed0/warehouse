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
import 'data/return_models.dart';
import 'data/return_providers.dart';

/// Returns (spec §16).
class ReturnsPlaceholderScreen extends ConsumerWidget {
  const ReturnsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(returnListControllerProvider);
    final controller = ref.read(returnListControllerProvider.notifier);

    final columns = <AppTableColumn<ProductReturn>>[
      AppTableColumn(label: l10n.fieldReturnNumber, cellBuilder: (context, item) => Text(item.returnNumber)),
      AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
      AppTableColumn(label: l10n.fieldCustomer, cellBuilder: (context, item) => Text(item.customerName ?? '—')),
      AppTableColumn(label: l10n.fieldRemainingAmount, numeric: true, cellBuilder: (context, item) => Text(item.refundAmount.toStringAsFixed(2))),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
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
      ),
    ];

    return PageScaffold(
      title: l10n.navReturns,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navReturns}', icon: Icons.add, onPressed: () => context.push(AppRoutes.returnNew)),
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<ProductReturn>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            onRowTap: (item) => context.push(AppRoutes.returnDetail(item.id)),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage),
        ],
      ),
    );
  }
}
