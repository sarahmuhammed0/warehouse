import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/providers.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'category_models.dart';
import 'api_category_repository.dart';
import 'category_repository.dart';

/// One shared instance for the app's lifetime — swapping this provider's
/// override in `main.dart`/tests is the entire mechanism for later pointing
/// the whole Categories module at a real API instead of local demo data.
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiCategoryRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalCategoryRepository(),
  };
});

final categoryListControllerProvider =
    NotifierProvider<CategoryListController, PagedListState<Category>>(CategoryListController.new);

class CategoryListController extends PagedListController<Category> {
  @override
  Future<PaginatedResult<Category>> fetch(PagedQuery query) {
    return ref.read(categoryRepositoryProvider).list(query);
  }

  Future<void> setStatus(String id, CategoryStatus status) async {
    await ref.read(categoryRepositoryProvider).setStatus(id, status);
    await reload();
  }
}

/// A separate, unpaginated provider for parent-category dropdowns — reusing
/// [categoryListControllerProvider] (paginated) would only ever show one
/// page's worth of options.
final categoryPickerOptionsProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).allForPicker();
});
