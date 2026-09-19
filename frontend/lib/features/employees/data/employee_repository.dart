import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'employee_models.dart';

abstract class EmployeeRepository {
  Future<PaginatedResult<Employee>> list(PagedQuery query);
  Future<Employee> create(EmployeeDraft draft);
  Future<Employee> update(String id, EmployeeDraft draft);
  Future<void> setStatus(String id, EmployeeStatus status);

  Future<List<Role>> listRoles();
  Future<Role> updateRolePermissions(String roleId, Set<String> permissions);
}

class LocalEmployeeRepository with DemoRepository implements EmployeeRepository {
  LocalEmployeeRepository() {
    _seedRoles();
    _seedEmployees();
  }

  final List<Employee> _items = [];
  final List<Role> _roles = [];
  int _nextId = 1;

  void _seedRoles() {
    Set<String> allFor(List<String> modules, List<String> actions) => {
          for (final m in modules)
            for (final a in actions)
              if (PermissionCatalog.supports(m, a)) PermissionCatalog.key(m, a),
        };

    _roles.addAll([
      Role(id: 'role-owner', name: 'Business Owner/Admin', isSystemRole: true, permissions: allFor(PermissionCatalog.modules, PermissionCatalog.actions)),
      Role(id: 'role-manager', name: 'Manager', isSystemRole: true, permissions: allFor(['products', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'reports'], ['view', 'create', 'edit'])),
      Role(id: 'role-warehouse', name: 'Warehouse Manager', isSystemRole: true, permissions: allFor(['products', 'inventory'], ['view', 'create', 'edit', 'delete']).union(allFor(['sales', 'orders'], ['view']))),
      Role(id: 'role-sales', name: 'Sales Staff', isSystemRole: true, permissions: allFor(['sales', 'orders'], ['view', 'create', 'edit']).union(allFor(['customers', 'products'], ['view']))),
      Role(id: 'role-inventory', name: 'Inventory Staff', isSystemRole: true, permissions: allFor(['inventory'], ['view', 'edit']).union(allFor(['products'], ['view']))),
      Role(id: 'role-production', name: 'Production Manager', isSystemRole: true, permissions: allFor(['production'], ['view', 'create', 'edit', 'delete']).union(allFor(['inventory'], ['view']))),
      Role(id: 'role-accountant', name: 'Accountant', isSystemRole: true, permissions: allFor(['reports'], ['view', 'export']).union(allFor(['purchases'], ['view', 'approve']))),
      Role(id: 'role-viewer', name: 'Viewer', isSystemRole: true, permissions: allFor(PermissionCatalog.modules, ['view'])),
    ]);
  }

  void _seedEmployees() {
    final now = DateTime.now();
    final seed = [
      ('Demo Admin', '+9647701112233', 'role-owner'),
      ('Zana Hussein', '+9647709998877', 'role-manager'),
      ('Rezan Ali', '+9647701234500', 'role-warehouse'),
      ('Dilan Omar', '+9647705556677', 'role-sales'),
    ];
    for (final (name, phone, roleId) in seed) {
      _items.add(
        Employee(
          id: 'emp-${_nextId++}',
          name: name,
          phone: phone,
          email: null,
          roleId: roleId,
          roleName: _roles.firstWhere((r) => r.id == roleId).name,
          status: EmployeeStatus.active,
          lastLoginAt: now.subtract(const Duration(hours: 5)),
          createdAt: now,
        ),
      );
    }
  }

  @override
  Future<PaginatedResult<Employee>> list(PagedQuery query) async {
    await simulatedLatency();
    final pool = List<Employee>.from(_items);
    return paginateInMemory<Employee>(pool, query, matches: (item, q) => item.name.toLowerCase().contains(q) || item.phone.contains(q), sortKey: (item) => item.name);
  }

  @override
  Future<Employee> create(EmployeeDraft draft) async {
    await simulatedLatency();
    final role = _roles.firstWhere((r) => r.id == draft.roleId);
    final created = Employee(id: 'emp-${_nextId++}', name: draft.name, phone: draft.phone, email: draft.email, roleId: role.id, roleName: role.name, status: draft.status, createdAt: DateTime.now());
    _items.add(created);
    return created;
  }

  @override
  Future<Employee> update(String id, EmployeeDraft draft) async {
    await simulatedLatency();
    final index = _items.indexWhere((e) => e.id == id);
    if (index == -1) throw StateError('Employee not found');
    final role = _roles.firstWhere((r) => r.id == draft.roleId);
    final existing = _items[index];
    final updated = Employee(id: existing.id, name: draft.name, phone: draft.phone, email: draft.email, roleId: role.id, roleName: role.name, status: draft.status, lastLoginAt: existing.lastLoginAt, createdAt: existing.createdAt);
    _items[index] = updated;
    return updated;
  }

  @override
  Future<void> setStatus(String id, EmployeeStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((e) => e.id == id);
    if (index == -1) throw StateError('Employee not found');
    final existing = _items[index];
    _items[index] = Employee(id: existing.id, name: existing.name, phone: existing.phone, email: existing.email, roleId: existing.roleId, roleName: existing.roleName, status: status, lastLoginAt: existing.lastLoginAt, createdAt: existing.createdAt);
  }

  @override
  Future<List<Role>> listRoles() async {
    await simulatedLatency();
    return _roles;
  }

  @override
  Future<Role> updateRolePermissions(String roleId, Set<String> permissions) async {
    await simulatedLatency();
    final index = _roles.indexWhere((r) => r.id == roleId);
    if (index == -1) throw StateError('Role not found');
    _roles[index] = _roles[index].copyWith(permissions: permissions);
    return _roles[index];
  }
}
