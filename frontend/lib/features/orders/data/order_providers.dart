import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/network/providers.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'api_order_repository.dart';
import 'order_models.dart';
import 'order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiOrderRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalOrderRepository(),
  };
});

final orderListControllerProvider =
    NotifierProvider<OrderListController, PagedListState<Order>>(OrderListController.new);

class OrderListController extends PagedListController<Order> {
  @override
  Future<PaginatedResult<Order>> fetch(PagedQuery query) {
    return ref.read(orderRepositoryProvider).list(query);
  }

  Future<void> updateStatus(String id, OrderStatus status) async {
    await ref.read(orderRepositoryProvider).updateStatus(id, status);
    await reload();
  }
}

final orderByIdProvider = FutureProvider.autoDispose.family<Order, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).getById(id);
});

/// For Returns' order picker — completed orders only (a return only makes
/// sense against an order that was actually fulfilled).
final completedOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final result = await ref.watch(orderRepositoryProvider).list(const PagedQuery(pageSize: 100));
  return result.items.where((o) => o.status == OrderStatus.completed).toList();
});
