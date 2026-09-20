import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/forms/app_select_field.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../shared/tables/table_row_actions.dart';
import 'data/admin_business_models.dart';
import 'data/admin_providers.dart';

/// System Admin's business list (spec §2). Creation of a new business is
/// backend-only in this frontend-first phase — see
/// `docs/frontend-backend-contract-notes.md`; System Admin already had a
/// real `POST /api/admin/businesses` endpoint from Phase 2, so this screen
/// will connect to it directly once backend integration resumes.
class AdminBusinessesScreen extends ConsumerWidget {
  const AdminBusinessesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(adminBusinessListControllerProvider);
    final controller = ref.read(adminBusinessListControllerProvider.notifier);

    final columns = <AppTableColumn<AdminBusiness>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldModule, cellBuilder: (context, item) => Text(item.businessType)),
      AppTableColumn(label: l10n.fieldPhone, cellBuilder: (context, item) => Text(item.phone)),
      AppTableColumn(label: l10n.navProducts, numeric: true, cellBuilder: (context, item) => Text('${item.productCount}')),
      AppTableColumn(label: l10n.fieldEmployee, numeric: true, cellBuilder: (context, item) => Text('${item.userCount}')),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: item.status == BusinessAccountStatus.active ? l10n.statusActive : l10n.statusDisabled,
          tone: item.status == BusinessAccountStatus.active ? StatusTone.success : StatusTone.danger,
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.adminNavBusinesses,
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      filterBar: SizedBox(
        width: 200,
        child: AppDropdownField<BusinessAccountStatus?>(
          label: l10n.fieldStatus,
          value: state.query.filters['status'] as BusinessAccountStatus?,
          options: [
            AppSelectOption<BusinessAccountStatus?>(null, l10n.allOption),
            AppSelectOption<BusinessAccountStatus?>(BusinessAccountStatus.active, l10n.statusActive),
            AppSelectOption<BusinessAccountStatus?>(BusinessAccountStatus.disabled, l10n.statusDisabled),
          ],
          onChanged: (value) => controller.setFilters({...state.query.filters, 'status': value}),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<AdminBusiness>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            onRowTap: (item) => context.push(AppRoutes.adminBusinessDetail(item.id)),
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                RowAction(label: l10n.view, icon: Icons.visibility_outlined, onTap: () => context.push(AppRoutes.adminBusinessDetail(item.id))),
                if (item.status == BusinessAccountStatus.active)
                  RowAction(label: l10n.deactivate, icon: Icons.block_outlined, destructive: true, onTap: () => controller.setStatus(item.id, BusinessAccountStatus.disabled))
                else
                  RowAction(label: l10n.activate, icon: Icons.check_circle_outline, onTap: () => controller.setStatus(item.id, BusinessAccountStatus.active)),
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
