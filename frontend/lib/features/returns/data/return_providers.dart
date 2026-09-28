import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/providers.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'return_models.dart';
import 'api_return_repository.dart';
import 'return_repository.dart';

final returnRepositoryProvider = Provider<ReturnRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiReturnRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalReturnRepository(),
  };
});

final returnListControllerProvider =
    NotifierProvider<ReturnListController, PagedListState<ProductReturn>>(ReturnListController.new);

class ReturnListController extends PagedListController<ProductReturn> {
  @override
  Future<PaginatedResult<ProductReturn>> fetch(PagedQuery query) {
    return ref.read(returnRepositoryProvider).list(query);
  }

  Future<void> updateStatus(String id, ReturnStatus status) async {
    await ref.read(returnRepositoryProvider).updateStatus(id, status);
    await reload();
  }
}

final returnByIdProvider = FutureProvider.autoDispose.family<ProductReturn, String>((ref, id) {
  return ref.watch(returnRepositoryProvider).getById(id);
});
