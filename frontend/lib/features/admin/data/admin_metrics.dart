import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/demo_businesses.dart';
import '../../employees/data/employee_providers.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../products/data/product_providers.dart';

/// Per-business record counts for the System Admin's overview screens.
///
/// These are **derived**, never seeded: every number here is the length of
/// a real list returned by the same demo repositories the business-side
/// screens read (`listForBusiness`). That's deliberate — the drill-down's
/// whole promise is that a number on a card is the number of rows you get
/// when you tap it, so there must be exactly one place the number comes
/// from. A hard-coded `productCount` on the business record would be a
/// second, silently diverging source of truth, which is why
/// `AdminBusiness` no longer carries one.
class BusinessMetrics {
  const BusinessMetrics({
    required this.businessId,
    required this.employeeCount,
    required this.productCount,
    required this.orderCount,
    required this.salesCount,
    required this.salesTotal,
  });

  final String businessId;
  final int employeeCount;
  final int productCount;

  /// Standard orders only — mirrors the Orders module's own filter.
  final int orderCount;

  /// Quick-sale orders only — mirrors the Sales module's own filter.
  final int salesCount;

  /// Revenue of those quick sales (their grand totals).
  final double salesTotal;
}

/// Every business's metrics plus the platform-wide totals the dashboard
/// stat cards show. Totals are sums of the per-business rows, so the
/// dashboard number and the overview rows can never disagree.
class AdminMetrics {
  const AdminMetrics(
    this.byBusiness, {
    this.monthlySales = const [],
    this.monthlyOrders = const [],
  });

  final Map<String, BusinessMetrics> byBusiness;

  /// The last twelve months of platform-wide quick-sale revenue, oldest
  /// first, and the matching count of standard orders. The dashboard's
  /// range control plots a tail of these rather than re-querying, so
  /// switching period is instant and every period is folded from one pass
  /// over the records.
  ///
  /// Derived from the very same order rows the per-business counts above
  /// are folded from — there is no separate "platform sales" dataset, and
  /// inventing one is how a dashboard ends up disagreeing with the records
  /// behind it. A month with nothing in it is a real zero, not a gap.
  final List<({String label, double value})> monthlySales;
  final List<({String label, double value})> monthlyOrders;

  BusinessMetrics forBusiness(String businessId) =>
      byBusiness[businessId] ??
      BusinessMetrics(businessId: businessId, employeeCount: 0, productCount: 0, orderCount: 0, salesCount: 0, salesTotal: 0);

  int _sum(int Function(BusinessMetrics) field) => byBusiness.values.fold(0, (total, m) => total + field(m));

  int get totalEmployees => _sum((m) => m.employeeCount);
  int get totalProducts => _sum((m) => m.productCount);
  int get totalOrders => _sum((m) => m.orderCount);
  int get totalSalesRecords => _sum((m) => m.salesCount);
  double get totalSalesAmount => byBusiness.values.fold(0, (total, m) => total + m.salesTotal);
}

/// How far back the platform series reaches. The dashboard offers shorter
/// ranges by taking a tail of it.
const int kAdminMonthsTracked = 12;

/// Not `.autoDispose`: this is watched by the dashboard and by every
/// overview screen, and re-fetching it on each navigation would make the
/// number visibly flicker between screens that are supposed to agree.
final adminMetricsProvider = FutureProvider<AdminMetrics>((ref) async {
  final employees = ref.watch(employeeRepositoryProvider);
  final products = ref.watch(productRepositoryProvider);
  final orders = ref.watch(orderRepositoryProvider);

  final result = <String, BusinessMetrics>{};
  // Kept so the platform series below is folded from exactly the rows that
  // produced the per-business counts.
  final allSales = <Order>[];
  final allOrders = <Order>[];

  for (final business in kDemoBusinesses) {
    final employeeRows = await employees.listForBusiness(business.id);
    final productRows = await products.listForBusiness(business.id);
    final orderRows = await orders.listForBusiness(business.id, type: OrderType.standard);
    final saleRows = await orders.listForBusiness(business.id, type: OrderType.quickSale);
    allSales.addAll(saleRows);
    allOrders.addAll(orderRows);
    result[business.id] = BusinessMetrics(
      businessId: business.id,
      employeeCount: employeeRows.length,
      productCount: productRows.length,
      orderCount: orderRows.length,
      salesCount: saleRows.length,
      salesTotal: saleRows.fold<double>(0, (total, o) => total + o.grandTotal),
    );
  }
  final now = DateTime.now();
  final monthlySales = <({String label, double value})>[];
  final monthlyOrders = <({String label, double value})>[];
  for (var i = kAdminMonthsTracked - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    bool inMonth(Order o) => o.createdAt.year == month.year && o.createdAt.month == month.month;
    // Same label shape the business dashboard's monthly series uses, so the
    // two read alike across the product.
    final label = '${month.month}/${month.year % 100}';
    monthlySales.add((
      label: label,
      value: allSales.where(inMonth).fold<double>(0, (sum, o) => sum + o.grandTotal),
    ));
    monthlyOrders.add((
      label: label,
      value: allOrders.where(inMonth).length.toDouble(),
    ));
  }

  return AdminMetrics(result, monthlySales: monthlySales, monthlyOrders: monthlyOrders);
});
