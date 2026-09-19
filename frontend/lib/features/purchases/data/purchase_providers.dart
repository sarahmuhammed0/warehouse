import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'purchase_models.dart';
import 'purchase_repository.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) => LocalPurchaseRepository());

final purchaseListControllerProvider =
    NotifierProvider<PurchaseListController, PagedListState<Purchase>>(PurchaseListController.new);

class PurchaseListController extends PagedListController<Purchase> {
  @override
  Future<PaginatedResult<Purchase>> fetch(PagedQuery query) {
    return ref.read(purchaseRepositoryProvider).list(query);
  }

  Future<void> updateStatus(String id, PurchaseStatus status) async {
    await ref.read(purchaseRepositoryProvider).updateStatus(id, status);
    await reload();
  }
}

final purchaseByIdProvider = FutureProvider.autoDispose.family<Purchase, String>((ref, id) {
  return ref.watch(purchaseRepositoryProvider).getById(id);
});
