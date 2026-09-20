import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_businesses.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'employee_models.dart';

abstract class EmployeeRepository {
  Future<PaginatedResult<Employee>> list(PagedQuery query);
  Future<Employee> create(EmployeeDraft draft);
  Future<Employee> update(String id, EmployeeDraft draft);
  Future<void> setStatus(String id, EmployeeStatus status);

  /// One tenant's employees — the System Admin's per-business Employees
  /// drill-down. See `ProductRepository.listForBusiness`.
  Future<List<Employee>> listForBusiness(String businessId);

  /// One employee by id, for the admin's individual-record view. The
  /// business-side Users screen edits in place and never needed this.
  Future<Employee> getById(String id);

  /// The link `permission_providers.dart` uses to resolve a signed-in
  /// account's role/permissions — a demo login's phone (see
  /// `demo_auth_repository.dart`) matches an `Employee.phone` seeded here.
  Future<Employee?> getByPhone(String phone);

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

  /// A synchronous counterpart to [getByPhone] + [listRoles], for
  /// `permission_providers.dart`'s `currentRoleProvider` only — that
  /// provider is watched from inside `routing/app_router.dart`'s
  /// `_enabledBusinessNavItems`, which runs as part of building the
  /// `GoRouter` itself. An async (`FutureProvider`) round trip there is
  /// genuinely dangerous, not just slower: `routerProvider`'s first
  /// Loading→Data transition after a fresh navigation makes it rebuild,
  /// which constructs a **brand new `GoRouter`** — discarding whatever
  /// route was just pushed and resetting to `initialLocation`. Found by
  /// actually testing the admin dashboard's Products/Orders/Sales/Employee
  /// cards (§ admin stat cards), which push into a business route the
  /// router had never rendered before — the exact case that triggered it.
  /// `_seedRoles()`/`_seedEmployees()` already run fully synchronously in
  /// the constructor above, so this has real data available immediately;
  /// only the OTHER interface methods add `simulatedLatency()` to mimic a
  /// real API for screens that actually fetch/paginate.
  Role? roleForPhoneSync(String phone) {
    for (final employee in _items) {
      if (employee.phone == phone) {
        for (final role in _roles) {
          if (role.id == employee.roleId) return role;
        }
        return null;
      }
    }
    return null;
  }

  void _seedRoles() {
    Set<String> allFor(List<String> modules, List<String> actions) => {
          for (final m in modules)
            for (final a in actions)
              if (PermissionCatalog.supports(m, a)) PermissionCatalog.key(m, a),
        };

    // Every role gets these three regardless of business-module access
    // (spec §23/§24 never ties Dashboard/Documents/Activity History
    // visibility to a specific role) — kept as one named set so it's
    // obvious at a glance which grants are "implicit for everyone" versus
    // the deliberately role-specific ones below.
    const implicitForEveryone = {'dashboard.view', 'documents.view', 'audit.view'};

    _roles.addAll([
      Role(id: 'role-owner', name: 'Business Owner/Admin', isSystemRole: true, permissions: allFor(PermissionCatalog.modules, PermissionCatalog.actions).union(implicitForEveryone)),
      Role(id: 'role-manager', name: 'Manager', isSystemRole: true, permissions: allFor(['products', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'reports'], ['view', 'create', 'edit']).union(implicitForEveryone)),
      Role(id: 'role-warehouse', name: 'Warehouse Manager', isSystemRole: true, permissions: allFor(['products', 'inventory'], ['view', 'create', 'edit', 'delete']).union(allFor(['sales', 'orders'], ['view'])).union(implicitForEveryone)),
      Role(id: 'role-sales', name: 'Sales Staff', isSystemRole: true, permissions: allFor(['sales', 'orders'], ['view', 'create', 'edit']).union(allFor(['customers', 'products'], ['view'])).union(implicitForEveryone)),
      Role(id: 'role-inventory', name: 'Inventory Staff', isSystemRole: true, permissions: allFor(['inventory'], ['view', 'edit']).union(allFor(['products'], ['view'])).union(implicitForEveryone)),
      Role(id: 'role-production', name: 'Production Manager', isSystemRole: true, permissions: allFor(['production'], ['view', 'create', 'edit', 'delete']).union(allFor(['inventory'], ['view'])).union(implicitForEveryone)),
      Role(id: 'role-accountant', name: 'Accountant', isSystemRole: true, permissions: allFor(['reports'], ['view', 'export']).union(allFor(['purchases'], ['view', 'approve'])).union(allFor(['financial'], ['view'])).union(implicitForEveryone)),
      Role(id: 'role-viewer', name: 'Viewer', isSystemRole: true, permissions: allFor(PermissionCatalog.modules.where((m) => m != 'financial').toList(), ['view']).union(implicitForEveryone)),
    ]);
  }

  void _seedEmployees() {
    final now = DateTime.now();
    // The first block's phone numbers deliberately match the demo-mode login
    // identities (`demo_auth_repository.dart`'s kDemoRolePhones) — see
    // `permission_providers.dart`'s doc comment for why: it's the link
    // between "who's signed in" and "what Role/permissions they have". They
    // all belong to the one business those demo logins sign into.
    //
    // The remaining blocks are staff of the other demo tenants. They are not
    // login identities (no matching phone in the demo auth repository); they
    // exist so the System Admin's per-business Employees drill-down shows
    // real, differing records per business rather than invented counts.
    // Never real E.164 numbers, same reasoning as the original two demo
    // identities.
    final seed = <(String, String, String, String, EmployeeStatus)>[
      (kDemoBusinessKarwan, 'Demo Owner', '+9647000000001', 'role-owner', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Zana Hussein', '+9647000000003', 'role-manager', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Rezan Ali', '+9647000000004', 'role-warehouse', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Dilan Omar', '+9647000000005', 'role-sales', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Ary Karim', '+9647000000006', 'role-inventory', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Soran Najat', '+9647000000007', 'role-production', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Lana Faraj', '+9647000000008', 'role-accountant', EmployeeStatus.active),
      (kDemoBusinessKarwan, 'Hero Salih', '+9647000000009', 'role-viewer', EmployeeStatus.active),

      (kDemoBusinessErbil, 'Shilan Aziz', '+9647100000001', 'role-owner', EmployeeStatus.active),
      (kDemoBusinessErbil, 'Karzan Tahir', '+9647100000002', 'role-warehouse', EmployeeStatus.active),
      (kDemoBusinessErbil, 'Nian Jamal', '+9647100000003', 'role-inventory', EmployeeStatus.active),
      (kDemoBusinessErbil, 'Bahar Sabir', '+9647100000004', 'role-sales', EmployeeStatus.inactive),

      (kDemoBusinessCityStore, 'Hemin Rauf', '+9647200000001', 'role-owner', EmployeeStatus.active),
      (kDemoBusinessCityStore, 'Avin Sarkawt', '+9647200000002', 'role-sales', EmployeeStatus.active),
      (kDemoBusinessCityStore, 'Rangin Sabah', '+9647200000003', 'role-viewer', EmployeeStatus.active),

      (kDemoBusinessNorthern, 'Diyar Mustafa', '+9647300000001', 'role-owner', EmployeeStatus.active),
      (kDemoBusinessNorthern, 'Payman Qadir', '+9647300000002', 'role-manager', EmployeeStatus.active),
      (kDemoBusinessNorthern, 'Trifa Nadir', '+9647300000003', 'role-inventory', EmployeeStatus.inactive),
    ];
    for (final (businessId, name, phone, roleId, status) in seed) {
      _items.add(
        Employee(
          id: 'emp-${_nextId++}',
          businessId: businessId,
          name: name,
          phone: phone,
          email: null,
          roleId: roleId,
          roleName: _roles.firstWhere((r) => r.id == roleId).name,
          status: status,
          lastLoginAt: status == EmployeeStatus.active ? now.subtract(const Duration(hours: 5)) : null,
          createdAt: now,
        ),
      );
    }
  }

  @override
  Future<List<Employee>> listForBusiness(String businessId) async {
    await simulatedLatency();
    return _items.where((e) => e.businessId == businessId).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<Employee> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((e) => e.id == id, orElse: () => throw StateError('Employee not found'));
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
    final created = Employee(id: 'emp-${_nextId++}', businessId: kDemoBusinessForNewRecords, name: draft.name, phone: draft.phone, email: draft.email, roleId: role.id, roleName: role.name, status: draft.status, createdAt: DateTime.now());
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
    final updated = Employee(id: existing.id, businessId: existing.businessId, name: draft.name, phone: draft.phone, email: draft.email, roleId: role.id, roleName: role.name, status: draft.status, lastLoginAt: existing.lastLoginAt, createdAt: existing.createdAt);
    _items[index] = updated;
    return updated;
  }

  @override
  Future<Employee?> getByPhone(String phone) async {
    await simulatedLatency();
    for (final e in _items) {
      if (e.phone == phone) return e;
    }
    return null;
  }

  @override
  Future<void> setStatus(String id, EmployeeStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((e) => e.id == id);
    if (index == -1) throw StateError('Employee not found');
    final existing = _items[index];
    _items[index] = Employee(id: existing.id, businessId: existing.businessId, name: existing.name, phone: existing.phone, email: existing.email, roleId: existing.roleId, roleName: existing.roleName, status: status, lastLoginAt: existing.lastLoginAt, createdAt: existing.createdAt);
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
