import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
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
