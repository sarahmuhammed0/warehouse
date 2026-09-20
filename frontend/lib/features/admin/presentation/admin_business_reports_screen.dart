import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/dashboard/dashboard_cards.dart';
import '../../../shared/dashboard/metric_cards.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/tables/app_data_table.dart';
import '../../../shared/tables/table_column.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../employees/data/employee_models.dart';
import '../../orders/data/order_models.dart';
import '../../products/data/product_models.dart';
import '../data/admin_metrics.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';

/// Spec §57's **View reports** control — reports for the *one* business the
/// System Admin is looking at, never a generic reports page.
///
/// Scope, stated honestly: §26 defines two report areas (Operational and
/// Business) across nine-odd categories. This screen reports the ones that
/// can be computed per business from real demo records — Products/Inventory,
/// Orders, Sales, Users. Purchases, Returns and Production are not tagged
/// with a `businessId` in the demo data (only products, orders and
/// employees are — see `core/repositories/demo_businesses.dart`), so
/// reporting them per business would mean inventing a split that the
/// underlying records do not have. The screen says so rather than showing a
/// number nothing backs.
class AdminBusinessReportsScreen extends ConsumerWidget {
  const AdminBusinessReportsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final businessAsync = ref.watch(adminBusinessByIdProvider(businessId));
    final metrics = ref.watch(adminMetricsProvider).asData?.value;

    return PageScaffold(
      // Business first, module second — the same heading shape the
      // drill-down's record screens use, so "whose reports am I reading" is
      // never in doubt.
      title: businessAsync.asData?.value.name ?? l10n.navReports,
      subtitle: l10n.navReports,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminBusinessDetail(businessId),
      body: businessAsync.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        error: (_, _) => AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessByIdProvider(businessId))),
        data: (business) {
          final row = metrics?.forBusiness(businessId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.lg,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final metric in AdminMetric.values)
                    SizedBox(
                      width: 200,
                      child: StatCard(
                        label: metric.label(l10n),
                        value: row == null
                            ? '—'
                            : metric == AdminMetric.sales
                                ? row.salesTotal.toStringAsFixed(2)
                                : '${metric.countFor(row)}',
                        icon: metric.icon,
                      ),
                    ),
                ],
              ),
              _InventoryReport(businessId: businessId),
              _SalesReport(businessId: businessId),
              _UsersReport(businessId: businessId),
              SectionCard(
                title: l10n.navReports,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(l10n.adminReportsScopeNotice, style: AppTypography.caption)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// §26 Operational → Inventory: this business's own stock position.
class _InventoryReport extends ConsumerWidget {
  const _InventoryReport({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessProductsProvider(businessId));
    final products = async.asData?.value ?? const <Product>[];
    final lowStock = products.where((p) => p.isLowStock).length;
    final outOfStock = products.where((p) => p.isOutOfStock).length;
    // Stock valuation at cost — §25's "Stock valuation", computed from this
    // business's real rows rather than asserted.
    final valuation = products.fold<double>(0, (sum, p) => sum + (p.currentQuantity * (p.purchaseCost ?? 0)));

    return SectionCard(
      title: l10n.navInventory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(width: 180, child: StatCard(label: l10n.statTotalProducts, value: '${products.length}', icon: Icons.inventory_2_outlined)),
              SizedBox(width: 180, child: StatCard(label: l10n.statusLowStock, value: '$lowStock', icon: Icons.trending_down)),
              SizedBox(width: 180, child: StatCard(label: l10n.statusOutOfStock, value: '$outOfStock', icon: Icons.remove_shopping_cart_outlined)),
              SizedBox(width: 180, child: StatCard(label: l10n.fieldPurchaseCost, value: valuation.toStringAsFixed(2), icon: Icons.attach_money)),
            ],
          ),
          if (async.hasError)
            AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessProductsProvider(businessId)))
          else if (products.isEmpty && async.hasValue)
            Text(l10n.adminReportsNoData, style: AppTypography.body)
          else
            AppDataTable<Product>(
              columns: [
                AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
                AppTableColumn(label: l10n.fieldCategory, cellBuilder: (context, item) => Text(item.categoryName)),
                AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.currentQuantity}')),
                AppTableColumn(
                  label: l10n.fieldStatus,
                  cellBuilder: (context, item) => StatusBadge(
                    label: item.isOutOfStock
                        ? l10n.statusOutOfStock
                        : item.isLowStock
                            ? l10n.statusLowStock
                            : l10n.statusActive,
                    tone: item.isOutOfStock
                        ? StatusTone.danger
                        : item.isLowStock
                            ? StatusTone.warning
                            : StatusTone.success,
                  ),
                ),
              ],
              rows: products,
              idOf: (item) => item.id,
              loading: async.isLoading,
              emptyTitle: l10n.adminReportsNoData,
            ),
        ],
      ),
    );
  }
}

/// §26 Business → Sales: this business's quick sales and what they earned.
class _SalesReport extends ConsumerWidget {
  const _SalesReport({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessSalesProvider(businessId));
    final sales = async.asData?.value ?? const <Order>[];
    final revenue = sales.fold<double>(0, (sum, o) => sum + o.grandTotal);

    return SectionCard(
      title: l10n.navSales,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(width: 180, child: StatCard(label: l10n.navSales, value: '${sales.length}', icon: Icons.point_of_sale_outlined)),
              SizedBox(width: 180, child: StatCard(label: l10n.fieldGrandTotal, value: revenue.toStringAsFixed(2), icon: Icons.trending_up)),
            ],
          ),
          if (async.hasError)
            AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessSalesProvider(businessId)))
          else
            AppDataTable<Order>(
              columns: [
                AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
                AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(_date(item.createdAt))),
                AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.grandTotal.toStringAsFixed(2))),
              ],
              rows: sales,
              idOf: (item) => item.id,
              loading: async.isLoading,
              emptyTitle: l10n.adminReportsNoData,
            ),
        ],
      ),
    );
  }
}

/// §57's "Users" statistic, reported: who this business's staff are.
class _UsersReport extends ConsumerWidget {
  const _UsersReport({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessEmployeesProvider(businessId));
    final employees = async.asData?.value ?? const <Employee>[];
    final active = employees.where((e) => e.status == EmployeeStatus.active).length;

    return SectionCard(
      title: l10n.navEmployees,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(width: 180, child: StatCard(label: l10n.navEmployees, value: '${employees.length}', icon: Icons.people_outline)),
              SizedBox(width: 180, child: StatCard(label: l10n.statusActive, value: '$active', icon: Icons.check_circle_outline)),
              SizedBox(width: 180, child: StatCard(label: l10n.statusInactive, value: '${employees.length - active}', icon: Icons.block_outlined)),
            ],
          ),
          if (async.hasError)
            AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessEmployeesProvider(businessId))),
        ],
      ),
    );
  }
}

String _date(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
