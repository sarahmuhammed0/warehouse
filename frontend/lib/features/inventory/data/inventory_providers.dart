import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import '../../products/data/product_providers.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return LocalInventoryRepository(ref.watch(productRepositoryProvider));
});

final warehousesProvider = FutureProvider.autoDispose<List<Warehouse>>((ref) {
  return ref.watch(inventoryRepositoryProvider).listWarehouses();
});

final movementListControllerProvider =
    NotifierProvider<MovementListController, PagedListState<StockMovement>>(MovementListController.new);

class MovementListController extends PagedListController<StockMovement> {
  @override
  Future<PaginatedResult<StockMovement>> fetch(PagedQuery query) {
    return ref.read(inventoryRepositoryProvider).listMovements(query);
  }
}

final transferListControllerProvider =
    NotifierProvider<TransferListController, PagedListState<StockTransfer>>(TransferListController.new);

class TransferListController extends PagedListController<StockTransfer> {
  @override
  Future<PaginatedResult<StockTransfer>> fetch(PagedQuery query) {
    return ref.read(inventoryRepositoryProvider).listTransfers(query);
  }
}
