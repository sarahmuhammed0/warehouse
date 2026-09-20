import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/tables/app_data_table.dart';
import '../../../shared/tables/table_column.dart';
import '../../employees/data/employee_models.dart';
import '../../orders/data/order_models.dart';
// The Orders module's own status label/tone mapping — reused rather than
// re-written, so an admin and the business see a status described the
// same way.
import '../../orders/orders_screen.dart' show orderStatusLabel, orderStatusTone;
import '../../products/data/product_models.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';

/// **Level 3** of the System Admin drill-down: the records of *one*
/// explicitly chosen business, for one metric.
///
/// This is an admin-shell screen, not the business app's own module screen.
/// That distinction is the point: the System Admin oversees records, so
/// these tables are read-only — no Add/Edit/Delete, no status transitions.
/// The business's own staff do that work in their shell, with their own
/// permissions (`docs/roles-and-permissions.md`).
class AdminBusinessRecordsScreen extends ConsumerWidget {
  const AdminBusinessRecordsScreen({super.key, required this.metric, required this.businessId});

  final AdminMetric metric;
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final businessAsync = ref.watch(adminBusinessByIdProvider(businessId));
    final businessName = businessAsync.asData?.value.name;

    return PageScaffold(
      // Titled by the business, subtitled by the module — the admin has just
      // chosen a business, so "whose records am I looking at" is the heading.
      title: businessName ?? metric.label(l10n),
      subtitle: businessName == null ? null : metric.label(l10n),
      showBackButton: true,
      backFallbackRoute: metric.overviewRoute,
      body: switch (metric) {
        AdminMetric.employees => _EmployeeRecords(businessId: businessId, metric: metric),
        AdminMetric.products => _ProductRecords(businessId: businessId, metric: metric),
        AdminMetric.orders || AdminMetric.sales => _OrderRecords(businessId: businessId, metric: metric),
      },
    );
  }
}

/// Shared loading/error/empty handling so the three record tables below
/// differ only in their columns.
class _RecordsBody<T> extends StatelessWidget {
  const _RecordsBody({
    required this.async,
    required this.onRetry,
    required this.columns,
    required this.idOf,
    required this.onRowTap,
  });

  final AsyncValue<List<T>> async;
  final VoidCallback onRetry;
  final List<AppTableColumn<T>> columns;
  final String Function(T) idOf;
  final void Function(T) onRowTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (async) {
      AsyncError() => AppErrorState(message: l10n.unableToLoad, onRetry: onRetry),
      AsyncData(:final value) => AppDataTable<T>(
          columns: columns,
          rows: value,
          idOf: idOf,
          emptyTitle: l10n.emptyStateDefaultTitle,
          emptyDescription: l10n.adminNoRecordsForBusiness,
          onRowTap: onRowTap,
        ),
      _ => AppDataTable<T>(columns: columns, rows: const [], idOf: idOf, loading: true, emptyTitle: l10n.emptyStateDefaultTitle),
    };
  }
}

class _EmployeeRecords extends ConsumerWidget {
  const _EmployeeRecords({required this.businessId, required this.metric});
  final String businessId;
  final AdminMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessEmployeesProvider(businessId));
    return _RecordsBody<Employee>(
      async: async,
      onRetry: () => ref.invalidate(adminBusinessEmployeesProvider(businessId)),
      idOf: (item) => item.id,
      onRowTap: (item) => context.push(metric.recordRoute(businessId, item.id)),
      columns: [
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
      ],
    );
  }
}

class _ProductRecords extends ConsumerWidget {
  const _ProductRecords({required this.businessId, required this.metric});
  final String businessId;
  final AdminMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessProductsProvider(businessId));
    return _RecordsBody<Product>(
      async: async,
      onRetry: () => ref.invalidate(adminBusinessProductsProvider(businessId)),
      idOf: (item) => item.id,
      onRowTap: (item) => context.push(metric.recordRoute(businessId, item.id)),
      columns: [
        AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
        AppTableColumn(label: l10n.fieldSku, cellBuilder: (context, item) => Text(item.sku ?? '—')),
        AppTableColumn(label: l10n.fieldCategory, cellBuilder: (context, item) => Text(item.categoryName)),
        AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.currentQuantity}')),
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
      ],
    );
  }
}

class _OrderRecords extends ConsumerWidget {
  const _OrderRecords({required this.businessId, required this.metric});
  final String businessId;
  final AdminMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Orders and Sales are one entity split by `orderType` (order_models.dart)
    // — the same split the business app's own Orders/Sales screens use, so an
    // order can never show up under both here.
    final provider = metric == AdminMetric.sales ? adminBusinessSalesProvider : adminBusinessOrdersProvider;
    final async = ref.watch(provider(businessId));
    return _RecordsBody<Order>(
      async: async,
      onRetry: () => ref.invalidate(provider(businessId)),
      idOf: (item) => item.id,
      onRowTap: (item) => context.push(metric.recordRoute(businessId, item.id)),
      columns: [
        AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
        AppTableColumn(label: l10n.fieldCustomer, cellBuilder: (context, item) => Text(item.customerName ?? '—')),
        AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.grandTotal.toStringAsFixed(2))),
        AppTableColumn(
          label: l10n.fieldStatus,
          cellBuilder: (context, item) => StatusBadge(label: orderStatusLabel(l10n, item.status), tone: orderStatusTone(item.status)),
        ),
      ],
    );
  }
}
