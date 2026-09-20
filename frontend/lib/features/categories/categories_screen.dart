import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/providers/permission_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/feedback/confirm_dialog.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../shared/tables/table_row_actions.dart';
import 'data/category_models.dart';
import 'data/category_providers.dart';
import 'presentation/category_form_dialog.dart';

/// Categories module (spec §7) — real CRUD against `LocalCategoryRepository`
/// (demo data, §48), built entirely on the shared `AppDataTable`/
/// `PageScaffold`/form-dialog pattern so this file has zero table/pagination
/// logic of its own.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(categoryListControllerProvider);
    final controller = ref.read(categoryListControllerProvider.notifier);
    final permissions = ref.watch(currentPermissionsProvider);
    final canCreate = hasPermission(permissions, 'categories', 'create');
    final canEdit = hasPermission(permissions, 'categories', 'edit');
    final canDelete = hasPermission(permissions, 'categories', 'delete');

    final columns = <AppTableColumn<Category>>[
      AppTableColumn(
        label: l10n.fieldName,
        cellBuilder: (context, item) => Text(item.isSubcategory ? '— ${item.name}' : item.name),
      ),
      AppTableColumn(label: l10n.fieldCode, cellBuilder: (context, item) => Text(item.code)),
      AppTableColumn(
        label: l10n.fieldParentCategory,
        cellBuilder: (context, item) => Text(item.parentName ?? l10n.noneOption),
      ),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: item.status == CategoryStatus.active ? l10n.statusActive : l10n.statusInactive,
          tone: item.status == CategoryStatus.active ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navCategories,
      primaryAction: canCreate
          ? AppButton(
              label: '${l10n.add} ${l10n.navCategories}',
              icon: Icons.add,
              onPressed: () => showCategoryFormDialog(context),
            )
          : null,
      searchBar: SizedBox(
        width: 280,
        child: AppTextField(
          label: l10n.search,
          hintText: l10n.searchPlaceholder,
          onChanged: controller.search,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Category>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            emptyDescription: l10n.emptyStateDefaultDescription,
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                if (canEdit)
                  RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => showCategoryFormDialog(context, editing: item)),
                if (canEdit)
                  if (item.status == CategoryStatus.active)
                    RowAction(
                      label: l10n.deactivate,
                      icon: Icons.visibility_off_outlined,
                      onTap: () => controller.setStatus(item.id, CategoryStatus.inactive),
                    )
                  else
                    RowAction(
                      label: l10n.activate,
                      icon: Icons.visibility_outlined,
                      onTap: () => controller.setStatus(item.id, CategoryStatus.active),
                    ),
                if (canDelete)
                  RowAction(
                    label: l10n.archive,
                    icon: Icons.archive_outlined,
                    destructive: true,
                    onTap: () async {
                      final confirmed = await confirmAction(
                        context,
                        title: l10n.archiveConfirmTitle,
                        description: l10n.archiveConfirmDescription,
                        confirmLabel: l10n.archive,
                        cancelLabel: l10n.cancel,
                        isDestructive: true,
                      );
                      if (confirmed ?? false) controller.setStatus(item.id, CategoryStatus.inactive);
                    },
                  ),
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
