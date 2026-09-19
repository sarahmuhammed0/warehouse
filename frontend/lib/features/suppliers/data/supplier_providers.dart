import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'supplier_models.dart';
import 'supplier_repository.dart';

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) => LocalSupplierRepository());

final supplierListControllerProvider =
    NotifierProvider<SupplierListController, PagedListState<Supplier>>(SupplierListController.new);

class SupplierListController extends PagedListController<Supplier> {
  @override
  Future<PaginatedResult<Supplier>> fetch(PagedQuery query) {
    return ref.read(supplierRepositoryProvider).list(query);
  }

  Future<void> setStatus(String id, SupplierStatus status) async {
    await ref.read(supplierRepositoryProvider).setStatus(id, status);
    await reload();
  }
}

final supplierPickerOptionsProvider = FutureProvider.autoDispose<List<Supplier>>((ref) {
  return ref.watch(supplierRepositoryProvider).allForPicker();
});

final supplierByIdProvider = FutureProvider.autoDispose.family<Supplier, String>((ref, id) {
  return ref.watch(supplierRepositoryProvider).getById(id);
});
