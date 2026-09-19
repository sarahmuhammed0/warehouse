import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) => LocalEmployeeRepository());

final employeeListControllerProvider =
    NotifierProvider<EmployeeListController, PagedListState<Employee>>(EmployeeListController.new);

class EmployeeListController extends PagedListController<Employee> {
  @override
  Future<PaginatedResult<Employee>> fetch(PagedQuery query) {
    return ref.read(employeeRepositoryProvider).list(query);
  }

  Future<void> setStatus(String id, EmployeeStatus status) async {
    await ref.read(employeeRepositoryProvider).setStatus(id, status);
    await reload();
  }
}

final rolesProvider = FutureProvider.autoDispose<List<Role>>((ref) {
  return ref.watch(employeeRepositoryProvider).listRoles();
});
