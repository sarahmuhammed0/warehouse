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
import '../../shared/tables/table_row_actions.dart';
import 'data/supplier_models.dart';
import 'data/supplier_providers.dart';
import 'presentation/supplier_form_dialog.dart';

/// Suppliers (spec §19).
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(supplierListControllerProvider);
    final controller = ref.read(supplierListControllerProvider.notifier);

    final columns = <AppTableColumn<Supplier>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldCompany, cellBuilder: (context, item) => Text(item.company ?? '—')),
      AppTableColumn(label: l10n.fieldPhone, cellBuilder: (context, item) => Text(item.phone)),
      AppTableColumn(
        label: l10n.fieldOutstandingBalance,
        numeric: true,
        cellBuilder: (context, item) => Text(
          item.outstandingBalance.toStringAsFixed(2),
          style: TextStyle(color: item.outstandingBalance > 0 ? Theme.of(context).colorScheme.error : null),
        ),
      ),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: item.status == SupplierStatus.active ? l10n.statusActive : l10n.statusInactive,
          tone: item.status == SupplierStatus.active ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navSuppliers,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navSuppliers}', icon: Icons.add, onPressed: () => showSupplierFormDialog(context)),
      searchBar: SizedBox(
        width: 280,
        child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Supplier>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            emptyDescription: l10n.emptyStateDefaultDescription,
            onRowTap: (item) => context.push(AppRoutes.supplierDetail(item.id)),
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                RowAction(label: l10n.view, icon: Icons.visibility_outlined, onTap: () => context.push(AppRoutes.supplierDetail(item.id))),
                RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => showSupplierFormDialog(context, editing: item)),
                if (item.status == SupplierStatus.active)
                  RowAction(label: l10n.deactivate, icon: Icons.visibility_off_outlined, onTap: () => controller.setStatus(item.id, SupplierStatus.inactive))
                else
                  RowAction(label: l10n.activate, icon: Icons.visibility_outlined, onTap: () => controller.setStatus(item.id, SupplierStatus.active)),
              ],
            ),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(
              page: state.query.page,
              totalPages: state.totalPages,
              pageSize: state.query.pageSize,
              pageSizeOptions: const [10, 20, 50],
              onPageChanged: controller.changePage,
              onPageSizeChanged: controller.changePageSize,
            ),
        ],
      ),
    );
  }
}
