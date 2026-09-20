import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/permission_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/feedback/confirm_dialog.dart';
import '../../shared/forms/app_select_field.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/search/filter_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../shared/tables/table_row_actions.dart';
import '../categories/data/category_providers.dart';
import 'data/product_models.dart';
import 'data/product_providers.dart';

/// Products (spec §8) — the table anatomy the brief specifies exactly:
/// image, name, SKU, category, quantity, location, cost, selling price,
/// status, actions.
class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(productListControllerProvider);
    final controller = ref.read(productListControllerProvider.notifier);
    final categoriesAsync = ref.watch(categoryPickerOptionsProvider);
    // Permission-gated UI (spec §24) — see permission_providers.dart's doc
    // comment. `null` means unrestricted (real backend-mode sessions keep
    // today's behavior; nothing here can take capability away from them).
    final permissions = ref.watch(currentPermissionsProvider);
    final canCreate = hasPermission(permissions, 'products', 'create');
    final canEdit = hasPermission(permissions, 'products', 'edit');
    final canDelete = hasPermission(permissions, 'products', 'delete');
    final canViewFinancial = hasPermission(permissions, 'financial', 'view');
    final activeFilters = <FilterChipData>[
      if (state.query.filters['stock'] == 'low')
        FilterChipData(label: l10n.statusLowStock, onRemove: () => controller.setFilters({}))
      else if (state.query.filters['stock'] == 'out')
        FilterChipData(label: l10n.statusOutOfStock, onRemove: () => controller.setFilters({})),
    ];

    final columns = <AppTableColumn<Product>>[
      AppTableColumn(
        label: l10n.fieldImage,
        width: 56,
        showInMobileCard: false,
        cellBuilder: (context, item) => CircleAvatar(
          radius: 16,
          child: Icon(Icons.inventory_2_outlined, size: 16),
        ),
      ),
      AppTableColumn(label: l10n.fieldName, sortable: true, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldSku, cellBuilder: (context, item) => Text(item.sku ?? '—')),
      AppTableColumn(label: l10n.fieldCategory, cellBuilder: (context, item) => Text(item.categoryName)),
      AppTableColumn(
        label: l10n.fieldQuantity,
        numeric: true,
        cellBuilder: (context, item) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item.currentQuantity}'),
            if (item.isOutOfStock) ...[
              const SizedBox(width: 6),
              StatusBadge(label: l10n.statusOutOfStock, tone: StatusTone.danger),
            ] else if (item.isLowStock) ...[
              const SizedBox(width: 6),
              StatusBadge(label: l10n.statusLowStock, tone: StatusTone.warning),
            ],
          ],
        ),
      ),
      AppTableColumn(label: l10n.fieldLocation, cellBuilder: (context, item) => Text(item.shelfRackBin ?? '—')),
      if (canViewFinancial)
        AppTableColumn(
          label: l10n.fieldPurchaseCost,
          numeric: true,
          cellBuilder: (context, item) => Text(item.purchaseCost?.toStringAsFixed(2) ?? '—'),
        ),
      AppTableColumn(
        label: l10n.fieldSellingPrice,
        numeric: true,
        cellBuilder: (context, item) => Text(item.sellingPrice?.toStringAsFixed(2) ?? '—'),
      ),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: switch (item.status) {
            ProductStatus.active => l10n.statusActive,
            ProductStatus.inactive => l10n.statusInactive,
            ProductStatus.discontinued => l10n.statusCancelled,
          },
          tone: switch (item.status) {
            ProductStatus.active => StatusTone.success,
            ProductStatus.inactive => StatusTone.neutral,
            ProductStatus.discontinued => StatusTone.danger,
          },
        ),
      ),
    ];

    return PageScaffold(
      title: l10n.navProducts,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      primaryAction: canCreate
          ? AppButton(
              label: '${l10n.add} ${l10n.navProducts}',
              icon: Icons.add,
              onPressed: () => context.push(AppRoutes.productNew),
            )
          : null,
      searchBar: SizedBox(
        width: 280,
        child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search),
      ),
      filterBar: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          categoriesAsync.maybeWhen(
            data: (categories) => SizedBox(
              width: 200,
              child: AppDropdownField<String?>(
                label: l10n.fieldCategory,
                value: state.query.filters['categoryId'] as String?,
                options: [
                  AppSelectOption<String?>(null, l10n.allOption),
                  for (final c in categories) AppSelectOption<String?>(c.id, c.name),
                ],
                onChanged: (value) => controller.setFilters({...state.query.filters, 'categoryId': value}),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          AppFilterBar(
            activeFilters: activeFilters,
            onOpenFilters: () => controller.setFilters({...state.query.filters, 'stock': 'low'}),
            onClearAll: activeFilters.isEmpty ? null : () => controller.setFilters({}),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Product>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            emptyDescription: l10n.emptyStateDefaultDescription,
            onRowTap: (item) => context.push(AppRoutes.productDetail(item.id)),
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [
                RowAction(label: l10n.view, icon: Icons.visibility_outlined, onTap: () => context.push(AppRoutes.productDetail(item.id))),
                if (canEdit)
                  RowAction(label: l10n.edit, icon: Icons.edit_outlined, onTap: () => context.push(AppRoutes.productEdit(item.id))),
                if (canEdit)
                  if (item.status == ProductStatus.active)
                    RowAction(label: l10n.deactivate, icon: Icons.visibility_off_outlined, onTap: () => controller.setStatus(item.id, ProductStatus.inactive))
                  else
                    RowAction(label: l10n.activate, icon: Icons.visibility_outlined, onTap: () => controller.setStatus(item.id, ProductStatus.active)),
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
                      if (confirmed ?? false) controller.setStatus(item.id, ProductStatus.inactive);
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
