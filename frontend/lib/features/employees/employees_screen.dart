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
import 'data/employee_models.dart';
import 'data/employee_providers.dart';
import 'presentation/employee_form_dialog.dart';

/// Employees / Users (spec §23). Roles/permissions live at
/// `AppRoutes.roles` (`RolesScreen`) — a separate secondary action here
/// rather than a nested tab, since managing a role's permission matrix is a
/// distinct enough task from managing the employee list itself.
class EmployeesPlaceholderScreen extends ConsumerWidget {
  const EmployeesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(employeeListControllerProvider);
    final controller = ref.read(employeeListControllerProvider.notifier);

    final columns = <AppTableColumn<Employee>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldPhone, cellBuilder: (context, item) => Text(item.phone)),
      AppTableColumn(label: l10n.fieldRole, cellBuilder: (context, item) => Text(item.roleName)),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: item.status == EmployeeStatus.active ? l10n.statusActive : l10n.statusInactive,
          tone: item.status == EmployeeStatus.active ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navEmployees,
      // See ProductsScreen's identical showBackButton comment — only
      // visible when reached via a push (e.g. the admin dashboard's
      // Employee card), never on normal sidebar navigation.
      showBackButton: context.canPop(),
      backFallbackRoute: AppRoutes.adminDashboard,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navEmployees}', icon: Icons.add, onPressed: () => showEmployeeFormDialog(context)),
      secondaryActions: [
        AppButton(label: l10n.fieldRole, icon: Icons.admin_panel_settings_outlined, variant: AppButtonVariant.outline, onPressed: () => context.push(AppRoutes.roles)),
      ],
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Employee>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => showEmployeeFormDialog(context, editing: item)),
                if (item.status == EmployeeStatus.active)
                  RowAction(label: l10n.deactivate, icon: Icons.visibility_off_outlined, onTap: () => controller.setStatus(item.id, EmployeeStatus.inactive))
                else
                  RowAction(label: l10n.activate, icon: Icons.visibility_outlined, onTap: () => controller.setStatus(item.id, EmployeeStatus.active)),
              ],
            ),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage),
        ],
      ),
    );
  }
}
