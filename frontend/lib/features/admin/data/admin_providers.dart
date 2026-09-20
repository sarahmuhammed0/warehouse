import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import '../../employees/data/employee_models.dart';
import '../../employees/data/employee_providers.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import 'admin_business_models.dart';
import 'admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) => LocalAdminRepository());

final adminBusinessListControllerProvider =
    NotifierProvider<AdminBusinessListController, PagedListState<AdminBusiness>>(AdminBusinessListController.new);

class AdminBusinessListController extends PagedListController<AdminBusiness> {
  @override
  Future<PaginatedResult<AdminBusiness>> fetch(PagedQuery query) {
    return ref.read(adminRepositoryProvider).listBusinesses(query);
  }

  Future<void> setStatus(String id, BusinessAccountStatus status) async {
    await ref.read(adminRepositoryProvider).setBusinessStatus(id, status);
    await reload();
  }
}

final adminBusinessByIdProvider = FutureProvider.autoDispose.family<AdminBusiness, String>((ref, id) {
  return ref.watch(adminRepositoryProvider).getBusinessById(id);
});

final adminRecentActivityProvider = FutureProvider.autoDispose<List<SystemActivityEntry>>((ref) {
  return ref.watch(adminRepositoryProvider).recentActivity();
});

// ---------------------------------------------------------------------------
// Drill-down level 3 — one business's records.
//
// These read the SAME `listForBusiness` methods `admin_metrics.dart` counts,
// which is what guarantees "the count on the overview row equals the number
// of rows here". They are `family` providers keyed by business id: the admin
// has no per-business session, so the chosen business travels as a route
// parameter and nothing is held as ambient state that could go stale.
// ---------------------------------------------------------------------------

final adminBusinessEmployeesProvider = FutureProvider.autoDispose.family<List<Employee>, String>((ref, businessId) {
  return ref.watch(employeeRepositoryProvider).listForBusiness(businessId);
});

final adminBusinessProductsProvider = FutureProvider.autoDispose.family<List<Product>, String>((ref, businessId) {
  return ref.watch(productRepositoryProvider).listForBusiness(businessId);
});

/// Standard orders (the Orders module) for one business.
final adminBusinessOrdersProvider = FutureProvider.autoDispose.family<List<Order>, String>((ref, businessId) {
  return ref.watch(orderRepositoryProvider).listForBusiness(businessId, type: OrderType.standard);
});

/// Quick sales (the Sales module) for one business.
final adminBusinessSalesProvider = FutureProvider.autoDispose.family<List<Order>, String>((ref, businessId) {
  return ref.watch(orderRepositoryProvider).listForBusiness(businessId, type: OrderType.quickSale);
});

/// Level 4 for Employees. Products and Orders already have by-id providers
/// their own modules use (`productByIdProvider` / `orderByIdProvider`);
/// employees never needed one until the admin gained a record view.
final adminEmployeeByIdProvider = FutureProvider.autoDispose.family<Employee, String>((ref, id) {
  return ref.watch(employeeRepositoryProvider).getById(id);
});
