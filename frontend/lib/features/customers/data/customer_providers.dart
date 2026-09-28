import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/network/providers.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'api_customer_repository.dart';
import 'customer_models.dart';
import 'customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiCustomerRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalCustomerRepository(),
  };
});

final customerListControllerProvider =
    NotifierProvider<CustomerListController, PagedListState<Customer>>(CustomerListController.new);

class CustomerListController extends PagedListController<Customer> {
  @override
  Future<PaginatedResult<Customer>> fetch(PagedQuery query) {
    return ref.read(customerRepositoryProvider).list(query);
  }

  Future<void> setStatus(String id, CustomerStatus status) async {
    await ref.read(customerRepositoryProvider).setStatus(id, status);
    await reload();
  }
}

final customerPickerOptionsProvider = FutureProvider.autoDispose<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).allForPicker();
});

final customerByIdProvider = FutureProvider.autoDispose.family<Customer, String>((ref, id) {
  return ref.watch(customerRepositoryProvider).getById(id);
});
