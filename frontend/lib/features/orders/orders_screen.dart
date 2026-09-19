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
import 'data/order_models.dart';
import 'data/order_providers.dart';

/// Orders (spec §14) — full workflow orders (`orderType == standard`); the
/// Sales module (`features/sales`) is the same underlying repository
/// filtered to `quickSale`.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(orderListControllerProvider);
    final controller = ref.read(orderListControllerProvider.notifier);

    // Standard orders only — quick sales have their own screen/tab.
    final rows = state.items.where((o) => o.orderType == OrderType.standard).toList();

    final columns = <AppTableColumn<Order>>[
      AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
      AppTableColumn(label: l10n.fieldCustomer, cellBuilder: (context, item) => Text(item.customerName ?? '—')),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(_formatDate(item.createdAt))),
      AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.items.length}')),
      AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.grandTotal.toStringAsFixed(2))),
      AppTableColumn(label: l10n.fieldPaidAmount, numeric: true, cellBuilder: (context, item) => Text(item.paidAmount.toStringAsFixed(2))),
      AppTableColumn(label: l10n.fieldStatus, cellBuilder: (context, item) => StatusBadge(label: orderStatusLabel(l10n, item.status), tone: orderStatusTone(item.status))),
    ];

    return PageScaffold(
      title: l10n.navOrders,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navOrders}', icon: Icons.add, onPressed: () => context.push('/orders/new')),
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<Order>(
            columns: columns,
            rows: rows,
            idOf: (item) => item.id,
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
            onRowTap: (item) => context.push(AppRoutes.orderDetail(item.id)),
            rowActionsBuilder: (context, item) => TableRowActions(
              actions: [RowAction(label: l10n.view, icon: Icons.visibility_outlined, onTap: () => context.push(AppRoutes.orderDetail(item.id)))],
            ),
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage),
        ],
      ),
    );
  }
}

String orderStatusLabel(AppLocalizations l10n, OrderStatus status) => switch (status) {
      OrderStatus.draft => l10n.statusDraft,
      OrderStatus.pending => l10n.statusPending,
      OrderStatus.confirmed => l10n.statusConfirmed,
      OrderStatus.processing => l10n.statusProcessing,
      OrderStatus.ready => l10n.statusReady,
      OrderStatus.completed => l10n.statusCompleted,
      OrderStatus.cancelled => l10n.statusCancelled,
      OrderStatus.returned => l10n.statusReturned,
      OrderStatus.partiallyReturned => l10n.statusPartiallyReturned,
    };

StatusTone orderStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.draft => StatusTone.neutral,
      OrderStatus.pending => StatusTone.warning,
      OrderStatus.confirmed => StatusTone.info,
      OrderStatus.processing => StatusTone.info,
      OrderStatus.ready => StatusTone.info,
      OrderStatus.completed => StatusTone.success,
      OrderStatus.cancelled => StatusTone.danger,
      OrderStatus.returned => StatusTone.warning,
      OrderStatus.partiallyReturned => StatusTone.warning,
    };

String _formatDate(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
