import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/network/providers.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'api_employee_repository.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiEmployeeRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalEmployeeRepository(),
  };
});

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
  ref.watch(rolesVersionProvider);
  return ref.watch(employeeRepositoryProvider).listRoles();
});

/// Bumped whenever a role's permissions change.
///
/// `LocalEmployeeRepository` mutates roles in place, so nothing about the
/// repository's *identity* changes when one is edited — and Riverpod has no
/// way to know a cached derived value is now stale. Anything that depends
/// on role contents (the permission matrix, and crucially
/// `currentRoleProvider`, which decides what the signed-in user may see)
/// watches this counter so an edit propagates instead of sitting behind a
/// cache for the rest of the session.
final rolesVersionProvider = NotifierProvider<RolesVersionController, int>(RolesVersionController.new);

class RolesVersionController extends Notifier<int> {
  @override
  int build() => 0;

  /// Applies a permission change and tells everyone who cares.
  Future<void> updatePermissions(String roleId, Set<String> permissions) async {
    await ref.read(employeeRepositoryProvider).updateRolePermissions(roleId, permissions);
    state = state + 1;
  }
}
