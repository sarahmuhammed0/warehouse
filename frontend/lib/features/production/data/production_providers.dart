import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'production_models.dart';
import 'production_repository.dart';

final productionRepositoryProvider = Provider<ProductionRepository>((ref) => LocalProductionRepository());

final productionListControllerProvider =
    NotifierProvider<ProductionListController, PagedListState<ProductionOrder>>(ProductionListController.new);

class ProductionListController extends PagedListController<ProductionOrder> {
  @override
  Future<PaginatedResult<ProductionOrder>> fetch(PagedQuery query) {
    return ref.read(productionRepositoryProvider).list(query);
  }

  Future<void> updateStatus(String id, ProductionStatus status) async {
    await ref.read(productionRepositoryProvider).updateStatus(id, status);
    await reload();
  }
}

final productionByIdProvider = FutureProvider.autoDispose.family<ProductionOrder, String>((ref, id) {
  return ref.watch(productionRepositoryProvider).getById(id);
});

final bomForProductProvider = FutureProvider.autoDispose.family<List<BomLine>, String>((ref, productId) {
  return ref.watch(productionRepositoryProvider).bomFor(productId);
});
