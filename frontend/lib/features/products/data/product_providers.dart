import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'product_models.dart';
import 'product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) => LocalProductRepository());

final productListControllerProvider =
    NotifierProvider<ProductListController, PagedListState<Product>>(ProductListController.new);

class ProductListController extends PagedListController<Product> {
  @override
  Future<PaginatedResult<Product>> fetch(PagedQuery query) {
    return ref.read(productRepositoryProvider).list(query);
  }

  Future<void> setStatus(String id, ProductStatus status) async {
    await ref.read(productRepositoryProvider).setStatus(id, status);
    await reload();
  }
}

final productPickerOptionsProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).allForPicker();
});

final productByIdProvider = FutureProvider.autoDispose.family<Product, String>((ref, id) {
  return ref.watch(productRepositoryProvider).getById(id);
});
