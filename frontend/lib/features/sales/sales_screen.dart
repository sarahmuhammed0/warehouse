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
import '../orders/data/order_models.dart';
import '../orders/data/order_providers.dart';
import '../orders/orders_screen.dart' show OrderFilterBar, orderStatusLabel, orderStatusTone;

/// Sales (spec §13) — the fast-checkout view over the same `orders`
/// repository as the Orders module, filtered to `orderType == quickSale`
/// (architecture's resolved "Sale vs. Order" ambiguity: one table, one
/// pipeline, two filtered views — see `docs/architecture.md`).
class SalesPlaceholderScreen extends ConsumerWidget {
  const SalesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(orderListControllerProvider);
    final controller = ref.read(orderListControllerProvider.notifier);
    final rows = state.items.where((o) => o.orderType == OrderType.quickSale).toList();
    // See ProductsScreen's identical comment — reachable from both shells.

    final columns = <AppTableColumn<Order>>[
      AppTableColumn(label: l10n.fieldInvoiceNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(item.createdAt.toString().split(' ').first)),
      AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.grandTotal.toStringAsFixed(2))),
      AppTableColumn(
        label: l10n.fieldPaymentStatus,
        cellBuilder: (context, item) => StatusBadge(
          label: switch (item.paymentStatus) {
            PaymentStatus.paid => l10n.statusPaid,
            PaymentStatus.partiallyPaid => l10n.statusPartiallyPaid,
            PaymentStatus.unpaid => l10n.statusUnpaid,
          },
          tone: switch (item.paymentStatus) {
            PaymentStatus.paid => StatusTone.success,
            PaymentStatus.partiallyPaid => StatusTone.warning,
            PaymentStatus.unpaid => StatusTone.danger,
          },
        ),
      ),
      AppTableColumn(label: l10n.fieldStatus, cellBuilder: (context, item) => StatusBadge(label: orderStatusLabel(l10n, item.status), tone: orderStatusTone(item.status))),
    ];

    return PageScaffold(
      title: l10n.navSales,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      primaryAction: AppButton(label: '${l10n.add} ${l10n.navSales}', icon: Icons.point_of_sale_outlined, onPressed: () => context.push(AppRoutes.saleNew)),
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      filterBar: OrderFilterBar(state: state, controller: controller),
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
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage, onPageSizeChanged: controller.changePageSize),
        ],
      ),
    );
  }
}
