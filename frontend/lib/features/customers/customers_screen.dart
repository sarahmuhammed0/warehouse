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
import 'data/customer_models.dart';
import 'data/customer_providers.dart';
import 'presentation/customer_form_dialog.dart';

/// Customers (spec §18).
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(customerListControllerProvider);
    final controller = ref.read(customerListControllerProvider.notifier);

    final columns = <AppTableColumn<Customer>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.fullName)),
      AppTableColumn(label: l10n.fieldPhone, cellBuilder: (context, item) => Text(item.phone)),
      AppTableColumn(label: l10n.fieldCompany, cellBuilder: (context, item) => Text(item.company ?? '—')),
      AppTableColumn(
        label: l10n.fieldTotalPurchases,
        numeric: true,
        cellBuilder: (context, item) => Text(item.totalPurchases.toStringAsFixed(2)),
      ),
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
          label: item.status == CustomerStatus.active ? l10n.statusActive : l10n.statusInactive,
          tone: item.status == CustomerStatus.active ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navCustomers,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navCustomers}', icon: Icons.add, onPressed: () => showCustomerFormDialog(context)),
      searchBar: SizedBox(
        width: 280,
        child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Customer>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            emptyDescription: l10n.emptyStateDefaultDescription,
            onRowTap: (item) => context.push(AppRoutes.customerDetail(item.id)),
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                RowAction(label: l10n.view, icon: Icons.visibility_outlined, onTap: () => context.push(AppRoutes.customerDetail(item.id))),
                RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => showCustomerFormDialog(context, editing: item)),
                if (item.status == CustomerStatus.active)
                  RowAction(label: l10n.deactivate, icon: Icons.visibility_off_outlined, onTap: () => controller.setStatus(item.id, CustomerStatus.inactive))
                else
                  RowAction(label: l10n.activate, icon: Icons.visibility_outlined, onTap: () => controller.setStatus(item.id, CustomerStatus.active)),
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
