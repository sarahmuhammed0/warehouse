import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../shared/tables/table_row_actions.dart';
import '../../theme/app_typography.dart';
import '../products/data/product_models.dart';
import '../products/data/product_providers.dart';
import 'data/inventory_models.dart';
import 'data/inventory_providers.dart';
import '../../shared/buttons/app_button.dart';
import 'presentation/stock_adjustment_dialog.dart';
import 'presentation/transfer_form_dialog.dart';

/// Inventory (spec §10/§11/§12) — one screen, four tabs, matching the
/// module's own internal structure rather than four separate routes (the
/// brief's "Inventory dashboard / table / adjustment / history / transfers"
/// list is what the tabs below cover) so switching between them is instant,
/// no reload.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PageScaffold(
      title: l10n.navInventory,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.navInventory),
              Tab(text: l10n.fieldOrderHistory),
              Tab(text: l10n.fieldWarehouse),
              Tab(text: l10n.transfer),
            ],
          ),
          SizedBox(
            height: 640,
            child: TabBarView(
              controller: _tabController,
              children: const [
                _StockOverviewTab(),
                _MovementsTab(),
                _LocationsTab(),
                _TransfersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockOverviewTab extends ConsumerWidget {
  const _StockOverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(productListControllerProvider);
    final controller = ref.read(productListControllerProvider.notifier);

    final columns = <AppTableColumn<Product>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldWarehouse, cellBuilder: (context, item) => Text(item.warehouseName ?? '—')),
      AppTableColumn(
        label: l10n.fieldCurrentQuantity,
        numeric: true,
        cellBuilder: (context, item) => Text('${item.currentQuantity} ${item.unit}'),
      ),
      AppTableColumn(label: l10n.fieldReservedQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.reservedQuantity}')),
      AppTableColumn(label: l10n.fieldAvailableQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.availableQuantity}')),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) {
          if (item.isOutOfStock) return StatusBadge(label: l10n.statusOutOfStock, tone: StatusTone.danger);
          if (item.isLowStock) return StatusBadge(label: l10n.statusLowStock, tone: StatusTone.warning);
          if (item.isOverstock) return StatusBadge(label: l10n.statusOverstock, tone: StatusTone.info);
          return StatusBadge(label: l10n.statusInStock, tone: StatusTone.success);
        },
      ),
    ];

    // The dashboard's Low Stock / Out of Stock cards land here with the
    // filter already applied. Without a visible chip the user would be
    // looking at a subset with no indication of why, and no way back to
    // the full list — so the arriving filter announces and clears itself.
    final stockFilter = state.query.filters['stock'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Row(
          children: [
            SizedBox(
              width: 280,
              child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search),
            ),
            if (stockFilter != null) ...[
              const SizedBox(width: 12),
              InputChip(
                key: const ValueKey('inventoryStockFilterChip'),
                label: Text(stockFilter == 'low' ? l10n.statusLowStock : l10n.statusOutOfStock),
                onDeleted: () => controller.setFilters({...state.query.filters}..remove('stock')),
              ),
            ],
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: AppDataTable<Product>(
              columns: columns,
              rows: state.items,
              idOf: (item) => item.id,
              loading: state.loading,
              errorMessage: state.error,
              onRetry: controller.reload,
              emptyTitle: l10n.emptyStateDefaultTitle,
              rowActionsBuilder: (context, item) => TableRowActions(
                actions: [
                  RowAction(label: l10n.adjust, icon: Icons.tune, onTap: () => showStockAdjustmentDialog(context, item)),
                ],
              ),
            ),
          ),
        ),
        if (!state.loading && state.error == null)
          PaginationBar(
            page: state.query.page,
            totalPages: state.totalPages,
            pageSize: state.query.pageSize,
            pageSizeOptions: const [10, 20, 50],
            onPageChanged: controller.changePage,
          ),
      ],
    );
  }
}

class _MovementsTab extends ConsumerWidget {
  const _MovementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(movementListControllerProvider);
    final controller = ref.read(movementListControllerProvider.notifier);

    final columns = <AppTableColumn<StockMovement>>[
      AppTableColumn(label: l10n.fieldProduct, cellBuilder: (context, item) => Text(item.productName)),
      AppTableColumn(label: l10n.fieldModule, cellBuilder: (context, item) => Text(_movementLabel(l10n, item.type))),
      AppTableColumn(
        label: l10n.fieldQuantity,
        numeric: true,
        cellBuilder: (context, item) => Text('${item.previousQuantity} → ${item.newQuantity}'),
      ),
      AppTableColumn(label: l10n.fieldEmployee, cellBuilder: (context, item) => Text(item.userName)),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(_formatDateTime(item.dateTime))),
      AppTableColumn(label: l10n.fieldReferenceNumber, cellBuilder: (context, item) => Text(item.referenceNumber ?? '—')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: AppDataTable<StockMovement>(
              columns: columns,
              rows: state.items,
              idOf: (item) => item.id,
              loading: state.loading,
              errorMessage: state.error,
              onRetry: controller.reload,
              emptyTitle: l10n.emptyStateDefaultTitle,
              emptyDescription: l10n.demoDataNotice,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationsTab extends ConsumerWidget {
  const _LocationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider);
    return warehouses.when(
      data: (items) => ListView(
        children: [
          for (final wh in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                title: Row(
                  children: [
                    Expanded(child: Text(wh.name)),
                    if (wh.isPrimary) StatusBadge(label: l10n.statusActive, tone: StatusTone.info),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(wh.type, style: AppTypography.body),
                    if (wh.address != null) Text(wh.address!, style: AppTypography.caption),
                    Text('${wh.locationCount} storage locations', style: AppTypography.caption),
                  ],
                ),
              ),
            ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.unableToLoad)),
    );
  }
}

class _TransfersTab extends ConsumerWidget {
  const _TransfersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(transferListControllerProvider);
    final controller = ref.read(transferListControllerProvider.notifier);

    final columns = <AppTableColumn<StockTransfer>>[
      AppTableColumn(label: l10n.fieldTransferNumber, cellBuilder: (context, item) => Text(item.transferNumber)),
      AppTableColumn(label: l10n.fieldProduct, cellBuilder: (context, item) => Text(item.productName)),
      AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.quantity}')),
      AppTableColumn(label: l10n.fieldWarehouse, cellBuilder: (context, item) => Text('${item.fromWarehouse} → ${item.toWarehouse}')),
      AppTableColumn(
        label: l10n.fieldStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: switch (item.status) {
            TransferStatus.pending => l10n.statusPending,
            TransferStatus.inTransit => l10n.statusProcessing,
            TransferStatus.completed => l10n.statusCompleted,
            TransferStatus.cancelled => l10n.statusCancelled,
          },
          tone: switch (item.status) {
            TransferStatus.pending => StatusTone.warning,
            TransferStatus.inTransit => StatusTone.info,
            TransferStatus.completed => StatusTone.success,
            TransferStatus.cancelled => StatusTone.danger,
          },
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            key: const ValueKey('newTransfer'),
            label: '${l10n.add} ${l10n.transfer}',
            icon: Icons.add,
            onPressed: () => showTransferFormDialog(context),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: AppDataTable<StockTransfer>(
              columns: columns,
              rows: state.items,
              idOf: (item) => item.id,
              loading: state.loading,
              errorMessage: state.error,
              onRetry: controller.reload,
              emptyTitle: l10n.emptyStateDefaultTitle,
            ),
          ),
        ),
      ],
    );
  }
}

String _movementLabel(AppLocalizations l10n, MovementType type) => switch (type) {
      MovementType.purchase => l10n.navPurchases,
      MovementType.sale => l10n.navSales,
      MovementType.returnMovement => l10n.navReturns,
      MovementType.damage => l10n.statusRejected,
      MovementType.adjustment => l10n.adjust,
      MovementType.transfer => l10n.transfer,
      MovementType.production => l10n.navProduction,
      MovementType.manualIncrease => '+ ${l10n.adjust}',
      MovementType.manualDecrease => '- ${l10n.adjust}',
    };

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
