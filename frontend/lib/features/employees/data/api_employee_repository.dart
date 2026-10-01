import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'employee_models.dart';
import 'employee_repository.dart';

/// Staff (§23) and roles (§24) against the real backend.
///
/// One repository for both because the interface is one: the roles list is
/// what the staff form's role picker offers, so a screen that has this has
/// both.
class ApiEmployeeRepository implements EmployeeRepository {
  ApiEmployeeRepository(this._client);

  final ApiClient _client;

  /// The schema's word is `disabled`; this module's word is `inactive`. They
  /// mean the same thing — an account that exists and cannot sign in — and
  /// the translation lives here so neither side has to adopt the other's
  /// vocabulary.
  static EmployeeStatus _status(String? raw) =>
      raw == 'disabled' ? EmployeeStatus.inactive : EmployeeStatus.active;

  static String _statusKey(EmployeeStatus status) =>
      status == EmployeeStatus.inactive ? 'disabled' : 'active';

  static Employee _fromJson(Map<String, dynamic> json) => Employee(
    id: '${json['id']}',
    businessId: '${json['businessId']}',
    name: (json['name'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    email: json['email'] as String?,
    roleId: '${json['roleId']}',
    roleName: (json['roleName'] as String?) ?? '',
    status: _status(json['status'] as String?),
    lastLoginAt: DateTime.tryParse('${json['lastLoginAt']}'),
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
  );

  static Role _roleFromJson(Map<String, dynamic> json) => Role(
    id: '${json['id']}',
    name: (json['name'] as String?) ?? '',
    isSystemRole: json['isSystemRole'] as bool? ?? false,
    permissions: ((json['permissions'] as List<dynamic>?) ?? const []).map((e) => '$e').toSet(),
  );

  @override
  Future<PaginatedResult<Employee>> list(PagedQuery query) async {
    final result = await _client.getList('/users?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<Employee> getById(String id) async => _fromJson(await _client.getJson('/users/$id'));

  /// The server generates a first password and returns it exactly once, in
  /// this response (§23) — there is no mail transport, so an owner creating an
  /// account has to be able to read it and pass it on.
  ///
  /// [lastTemporaryPassword] is where it is left for the caller. It is held in
  /// memory on this repository and never written anywhere: a temporary
  /// password in storage is a temporary password in a backup.
  @override
  Future<Employee> create(EmployeeDraft draft) async {
    final response = await _client.postJson('/users', {
      'name': draft.name,
      'phone': draft.phone,
      'email': draft.email,
      'roleId': int.tryParse(draft.roleId) ?? draft.roleId,
      'status': _statusKey(draft.status),
    });
    lastTemporaryPassword = response['temporaryPassword'] as String?;
    return _fromJson(response);
  }

  /// The generated password from the most recent [create], or null if the
  /// caller supplied one. Read it immediately — the next create overwrites it.
  String? lastTemporaryPassword;

  /// A phone number is the credential (§3) and the identity, so the server
  /// does not accept a change to it — an owner who could rewrite a colleague's
  /// number could point their login at a phone they control.
  ///
  /// The form still shows the field, because it is what the account signs in
  /// with and hiding it would be worse. So an attempted change is refused
  /// **here**, loudly. It cannot be passed through and ignored: zod strips a
  /// key it does not know, so the request would return 200 with the phone
  /// unchanged, and the owner would leave believing they had changed it.
  @override
  Future<Employee> update(String id, EmployeeDraft draft) async {
    final current = await getById(id);
    if (draft.phone.trim() != current.phone.trim()) {
      throw const Failure(
        'PHONE_NOT_EDITABLE',
        "A phone number cannot be changed — it is what this account signs in with. "
            "Add a new account for a new number.",
      );
    }

    return _fromJson(
      await _client.patchJson('/users/$id', {
        'name': draft.name,
        'email': draft.email,
        'roleId': int.tryParse(draft.roleId) ?? draft.roleId,
        'status': _statusKey(draft.status),
      }),
    );
  }

  @override
  Future<void> setStatus(String id, EmployeeStatus status) async {
    await _client.patchJson('/users/$id', {'status': _statusKey(status)});
  }

  /// §57's per-business drill-down, through the admin endpoint that names the
  /// business — a business-side route is scoped to the caller's own session
  /// and a System Admin has no session-scoped business to be scoped to.
  @override
  Future<List<Employee>> listForBusiness(String businessId) async {
    final response = await _client.getJson('/admin/businesses/$businessId/users');
    return ((response['items'] as List<dynamic>?) ?? const [])
        .map((row) => _fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Demo-only. It exists so a demo login can be matched to a seeded employee
  /// and resolve its permissions; a real session is told its own role by the
  /// server (`/api/auth/me`), and there is no endpoint that looks a colleague
  /// up by phone — nor should there be, since that is an enumeration oracle
  /// over every user in the system.
  @override
  Future<Employee?> getByPhone(String phone) async => null;

  @override
  Future<List<Role>> listRoles() async {
    final result = await _client.getList('/roles');
    return result.data.map((row) => _roleFromJson(row as Map<String, dynamic>)).toList();
  }

  /// PUT, not PATCH: §24's permission grid is saved as a whole set. Two calls
  /// that must both succeed to leave a coherent role is how a role ends up
  /// half-granted.
  @override
  Future<Role> updateRolePermissions(String roleId, Set<String> permissions) async {
    return _roleFromJson(
      await _client.putJson('/roles/$roleId/permissions', {'permissions': permissions.toList()}),
    );
  }
}
