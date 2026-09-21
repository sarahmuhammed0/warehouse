import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repositories/paged_query.dart';
import '../../categories/data/category_providers.dart';
import '../../customers/data/customer_providers.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../products/data/product_providers.dart';
import '../../suppliers/data/supplier_providers.dart';

/// Every statistic spec §5 asks a business dashboard to show, derived from
/// the same demo repositories the modules themselves read.
///
/// One provider rather than fifteen scattered `ref.watch`es in the screen:
/// the dashboard's cards are drill-downs, so each number has to agree with
/// the filtered list it opens. Deriving them all from one snapshot of the
/// same repositories is what makes that true by construction — the same
/// reasoning as the System Admin's `admin_metrics.dart`.
class DashboardMetrics {
  const DashboardMetrics({
    required this.totalProducts,
    required this.totalCategories,
    required this.totalStockQuantity,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.todaysSalesTotal,
    required this.todaysOrderCount,
    required this.monthSalesTotal,
    required this.totalSalesTotal,
    required this.pendingOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.returnedOrders,
    required this.totalCustomers,
    required this.totalSuppliers,
    required this.dailySales,
    required this.monthlySales,
    required this.topProducts,
    required this.categorySales,
    required this.grossProfit,
  });

  final int totalProducts;
  final int totalCategories;
  final int totalStockQuantity;
  final int lowStockCount;
  final int outOfStockCount;

  /// "Sales" means quick-sale orders, the same split the Sales module uses.
  final double todaysSalesTotal;
  final int todaysOrderCount;
  final double monthSalesTotal;
  final double totalSalesTotal;

  final int pendingOrders;
  final int completedOrders;
  final int cancelledOrders;

  /// Returned *and* partially returned — both are "came back" from the
  /// dashboard's point of view, and the Orders filter it opens matches.
  final int returnedOrders;

  final int totalCustomers;
  final int totalSuppliers;

  /// Chart series (§5's "visual reports"). Each entry is one bar.
  final List<ChartPoint> dailySales;
  final List<ChartPoint> monthlySales;
  final List<ChartPoint> topProducts;
  final List<ChartPoint> categorySales;

  /// Revenue minus cost of the items sold, over every completed sale/order
  /// whose products carry a `purchaseCost`. Null when no product has cost
  /// data — §5 asks for profit "when cost data exists", and a zero would
  /// read as "you made nothing" rather than "this isn't known".
  final double? grossProfit;
}

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final double value;
}

/// Not `.autoDispose`: the dashboard and its drill-down targets both read
/// this, and re-deriving it on every navigation would make the numbers
/// visibly flicker between screens that are meant to agree.
final dashboardMetricsProvider = FutureProvider<DashboardMetrics>((ref) async {
  final products = await ref.watch(productRepositoryProvider).list(const PagedQuery(pageSize: 1000));
  final orders = await ref.watch(orderRepositoryProvider).list(const PagedQuery(pageSize: 1000));
  final customers = await ref.watch(customerPickerOptionsProvider.future);
  final suppliers = await ref.watch(supplierPickerOptionsProvider.future);
  final categories = await ref.watch(categoryPickerOptionsProvider.future);

  final productList = products.items;
  final orderList = orders.items;
  final costById = {for (final p in productList) p.id: p.purchaseCost};

  final now = DateTime.now();
  bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
  bool isThisMonth(DateTime d) => d.year == now.year && d.month == now.month;

  final sales = orderList.where((o) => o.orderType == OrderType.quickSale).toList();
  final standardOrders = orderList.where((o) => o.orderType == OrderType.standard).toList();

  int countStatus(bool Function(OrderStatus) test) => orderList.where((o) => test(o.status)).length;

  // ---- chart series -------------------------------------------------
  // Last 7 days of sales revenue, oldest first, including days with none
  // (a gap in a bar chart reads as missing data rather than a quiet day).
  final dailySales = <ChartPoint>[];
  for (var i = 6; i >= 0; i--) {
    final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    final total = sales
        .where((o) => o.createdAt.year == day.year && o.createdAt.month == day.month && o.createdAt.day == day.day)
        .fold<double>(0, (sum, o) => sum + o.grandTotal);
    dailySales.add(ChartPoint('${day.day}/${day.month}', total));
  }

  final monthlySales = <ChartPoint>[];
  for (var i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    final total = sales
        .where((o) => o.createdAt.year == month.year && o.createdAt.month == month.month)
        .fold<double>(0, (sum, o) => sum + o.grandTotal);
    monthlySales.add(ChartPoint('${month.month}/${month.year % 100}', total));
  }

  // Revenue per product and per category, over every order line.
  final revenueByProduct = <String, double>{};
  for (final order in orderList) {
    for (final item in order.items) {
      revenueByProduct.update(item.productName, (v) => v + item.lineTotal, ifAbsent: () => item.lineTotal);
    }
  }
  final topProducts = revenueByProduct.entries.map((e) => ChartPoint(e.key, e.value)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final categoryNameById = {for (final p in productList) p.id: p.categoryName};
  final revenueByCategory = <String, double>{};
  for (final order in orderList) {
    for (final item in order.items) {
      final category = categoryNameById[item.productId];
      if (category == null) continue;
      revenueByCategory.update(category, (v) => v + item.lineTotal, ifAbsent: () => item.lineTotal);
    }
  }
  final categorySales = revenueByCategory.entries.map((e) => ChartPoint(e.key, e.value)).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // ---- profit --------------------------------------------------------
  final anyCostKnown = productList.any((p) => p.purchaseCost != null);
  double? grossProfit;
  if (anyCostKnown) {
    var revenue = 0.0;
    var cost = 0.0;
    for (final order in orderList.where((o) => o.status == OrderStatus.completed)) {
      for (final item in order.items) {
        revenue += item.lineTotal;
        cost += (costById[item.productId] ?? 0) * item.quantity;
      }
    }
    grossProfit = revenue - cost;
  }

  return DashboardMetrics(
    totalProducts: productList.length,
    totalCategories: categories.length,
    totalStockQuantity: productList.fold<int>(0, (sum, p) => sum + p.currentQuantity),
    lowStockCount: productList.where((p) => p.isLowStock).length,
    outOfStockCount: productList.where((p) => p.isOutOfStock).length,
    todaysSalesTotal: sales.where((o) => isToday(o.createdAt)).fold<double>(0, (sum, o) => sum + o.grandTotal),
    todaysOrderCount: standardOrders.where((o) => isToday(o.createdAt)).length,
    monthSalesTotal: sales.where((o) => isThisMonth(o.createdAt)).fold<double>(0, (sum, o) => sum + o.grandTotal),
    totalSalesTotal: sales.fold<double>(0, (sum, o) => sum + o.grandTotal),
    pendingOrders: countStatus((s) => s == OrderStatus.pending),
    completedOrders: countStatus((s) => s == OrderStatus.completed),
    cancelledOrders: countStatus((s) => s == OrderStatus.cancelled),
    returnedOrders: countStatus((s) => s == OrderStatus.returned || s == OrderStatus.partiallyReturned),
    totalCustomers: customers.length,
    totalSuppliers: suppliers.length,
    dailySales: dailySales,
    monthlySales: monthlySales,
    topProducts: topProducts.take(6).toList(),
    categorySales: categorySales.take(6).toList(),
    grossProfit: grossProfit,
  );
});
