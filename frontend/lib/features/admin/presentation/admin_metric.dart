import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../data/admin_metrics.dart';

/// The four dashboard statistics that drill down per business.
///
/// One enum instead of four near-identical screen pairs: every level of the
/// drill-down is the same shape (aggregate → per-business summary →
/// that business's records → one record), and only the label, icon, count
/// and route differ. Keeping those four differences in one place is what
/// stops the levels from silently diverging — the count on an overview row
/// and the rows the same metric lists are read through this single
/// definition.
enum AdminMetric {
  employees,
  products,
  orders,
  sales;

  String label(AppLocalizations l10n) => switch (this) {
        AdminMetric.employees => l10n.navEmployees,
        AdminMetric.products => l10n.navProducts,
        AdminMetric.orders => l10n.navOrders,
        AdminMetric.sales => l10n.navSales,
      };

  IconData get icon => switch (this) {
        AdminMetric.employees => Icons.people_outline,
        AdminMetric.products => Icons.inventory_2_outlined,
        AdminMetric.orders => Icons.receipt_long_outlined,
        AdminMetric.sales => Icons.point_of_sale_outlined,
      };

  /// How many records of this metric one business has — the number shown on
  /// its overview row, and exactly the number of rows the next level lists.
  int countFor(BusinessMetrics metrics) => switch (this) {
        AdminMetric.employees => metrics.employeeCount,
        AdminMetric.products => metrics.productCount,
        AdminMetric.orders => metrics.orderCount,
        AdminMetric.sales => metrics.salesCount,
      };

  /// The platform-wide figure the dashboard card shows. Sales is the one
  /// metric whose headline number is money rather than a record count (a
  /// "Sales" statistic that meant "number of receipts" would be
  /// misleading), so its overview screen shows both: revenue per business
  /// and, in its own column, the record count that matches the rows.
  String totalLabel(AdminMetrics metrics) => switch (this) {
        AdminMetric.employees => '${metrics.totalEmployees}',
        AdminMetric.products => '${metrics.totalProducts}',
        AdminMetric.orders => '${metrics.totalOrders}',
        AdminMetric.sales => metrics.totalSalesAmount.toStringAsFixed(0),
      };

  /// Level 2 — the per-business summary this metric's dashboard card opens.
  String get overviewRoute => switch (this) {
        AdminMetric.employees => AppRoutes.adminEmployees,
        AdminMetric.products => AppRoutes.adminProducts,
        AdminMetric.orders => AppRoutes.adminOrders,
        AdminMetric.sales => AppRoutes.adminSales,
      };

  /// Level 3 — one business's records for this metric.
  String recordsRoute(String businessId) => switch (this) {
        AdminMetric.employees => AppRoutes.adminEmployeesFor(businessId),
        AdminMetric.products => AppRoutes.adminProductsFor(businessId),
        AdminMetric.orders => AppRoutes.adminOrdersFor(businessId),
        AdminMetric.sales => AppRoutes.adminSalesFor(businessId),
      };

  /// Level 4 — one record.
  String recordRoute(String businessId, String recordId) => switch (this) {
        AdminMetric.employees => AppRoutes.adminEmployeeDetail(businessId, recordId),
        AdminMetric.products => AppRoutes.adminProductDetail(businessId, recordId),
        AdminMetric.orders => AppRoutes.adminOrderDetail(businessId, recordId),
        AdminMetric.sales => AppRoutes.adminSaleDetail(businessId, recordId),
      };
}
