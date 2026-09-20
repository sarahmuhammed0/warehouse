/// Employees / Users (spec §23) + Permission system (spec §24). Permissions
/// are data (`{module}.{action}` strings held per role), never a hard-coded
/// `if (role == 'Manager')` anywhere in this codebase — see
/// `permission_providers.dart`'s doc comment for where that's enforced.
enum EmployeeStatus { active, inactive }

class Employee {
  const Employee({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    this.email,
    required this.roleId,
    required this.roleName,
    required this.status,
    this.lastLoginAt,
    required this.createdAt,
  });

  final String id;

  /// Owning tenant — see `Product.businessId`.
  final String businessId;
  final String name;
  final String phone;
  final String? email;
  final String roleId;
  final String roleName;
  final EmployeeStatus status;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
}

class EmployeeDraft {
  const EmployeeDraft({required this.name, required this.phone, this.email, required this.roleId, this.status = EmployeeStatus.active});
  final String name;
  final String phone;
  final String? email;
  final String roleId;
  final EmployeeStatus status;
}

/// Seeded system roles (spec §23's list) — editable per business, not fixed
/// in code (architecture §9: "permissions are data, not code"). The demo
/// repository seeds these as a starting point; a real backend would let a
/// business rename/adjust them.
class Role {
  const Role({required this.id, required this.name, required this.isSystemRole, required this.permissions});
  final String id;
  final String name;
  final bool isSystemRole;
  final Set<String> permissions;

  Role copyWith({Set<String>? permissions}) => Role(id: id, name: name, isSystemRole: isSystemRole, permissions: permissions ?? this.permissions);
}

/// The permission catalog (spec §24) — `{module}.{action}`. A module that
/// doesn't need a given action simply has no such entry, matching the
/// architecture's own rule ("Reports has no delete").
class PermissionCatalog {
  PermissionCatalog._();

  static const modules = ['products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'production', 'reports', 'users', 'settings', 'financial'];
  static const actions = ['view', 'create', 'edit', 'delete', 'approve', 'export'];

  /// Not every module supports every action — mirrors the architecture's
  /// "Reports has no delete" example. `financial` (spec §24's standalone
  /// "View Financial Information") is view-only by nature — there's nothing
  /// to create/edit/delete/approve/export, it's a visibility flag for
  /// cost/margin/balance figures other modules already show.
  static bool supports(String module, String action) {
    if (module == 'financial') return action == 'view';
    if (action == 'approve') return module == 'returns' || module == 'purchases';
    if (action == 'export') return module == 'reports';
    if (action == 'delete') return module != 'reports' && module != 'settings';
    return true;
  }

  static String key(String module, String action) => '$module.$action';
}
