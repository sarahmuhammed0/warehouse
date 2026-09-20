import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/presentation/providers/auth_controller.dart';
import '../auth/presentation/providers/auth_state.dart';
import '../auth/presentation/providers/permission_providers.dart';
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
    final permissions = ref.watch(currentPermissionsProvider);
    final canCreate = hasPermission(permissions, 'users', 'create');
    final canEdit = hasPermission(permissions, 'users', 'edit');
    // See ProductsScreen's identical comment — reachable from both shells.
    final authState = ref.watch(authControllerProvider);
    final isAdminSession = authState is AuthAuthenticated && authState.business == null;

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
      showBackButton: true,
      backFallbackRoute: isAdminSession ? AppRoutes.adminDashboard : AppRoutes.dashboard,
      primaryAction: canCreate ? AppButton(label: '${l10n.add} ${l10n.navEmployees}', icon: Icons.add, onPressed: () => showEmployeeFormDialog(context)) : null,
      secondaryActions: [
        if (canEdit)
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
                if (canEdit)
                  RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => showEmployeeFormDialog(context, editing: item)),
                if (canEdit)
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
