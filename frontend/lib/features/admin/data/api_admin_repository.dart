import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'admin_business_models.dart';
import 'admin_repository.dart';

/// §57's System Admin business management against the real backend.
///
/// Every call here names the business it acts on. A business-side route is
/// scoped to the caller's own session (§36), and a System Admin has no session
/// -scoped business — which is why these are separate endpoints rather than
/// the same ones with a wider scope.
class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._client);

  final ApiClient _client;

  static BusinessAccountStatus _status(String? raw) => switch (raw) {
    'disabled' => BusinessAccountStatus.disabled,
    'suspended' => BusinessAccountStatus.disabled,
    _ => BusinessAccountStatus.active,
  };

  static AdminBusiness _fromJson(Map<String, dynamic> json) => AdminBusiness(
    id: '${json['id']}',
    name: (json['name'] as String?) ?? '',
    businessType: (json['businessType'] as String?) ?? '',
    logoUrl: json['logoUrl'] as String?,
    phone: (json['phone'] as String?) ?? '',
    email: json['email'] as String?,
    address: json['address'] as String?,
    status: _status(json['status'] as String?),
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    // Deliberately not set. The server does not record when an owner's
    // password was last reset, and a timestamp invented here would be shown
    // on the detail screen as though it were a fact about the account.
    lastPasswordResetAt: null,
  );

  @override
  Future<PaginatedResult<AdminBusiness>> listBusinesses(PagedQuery query) async {
    final result = await _client.getList('/admin/businesses?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<AdminBusiness> getBusinessById(String id) async =>
      _fromJson(await _client.getJson('/admin/businesses/$id'));

  @override
  Future<void> setBusinessStatus(String id, BusinessAccountStatus status) async {
    await _client.patchJson('/admin/businesses/$id/status', {
      'status': status == BusinessAccountStatus.disabled ? 'disabled' : 'active',
    });
  }

  /// PUT, because §57's Edit screen submits the whole profile.
  @override
  Future<AdminBusiness> updateBusiness(String id, AdminBusinessDraft draft) async {
    return _fromJson(await _client.putJson('/admin/businesses/$id', {
      'name': draft.name,
      'businessType': draft.businessType,
      'phone': draft.phone,
      'email': draft.email,
      'address': draft.address,
    }));
  }

  /// Resets the OWNER's password and returns the generated one — once, in this
  /// response, for the admin to pass on. It is not stored and re-reading the
  /// business will never return it again.
  ///
  /// [lastGeneratedPassword] is where the caller can find it.
  @override
  Future<AdminBusiness> resetBusinessPassword(String id) async {
    final response = await _client.postJson('/admin/businesses/$id/reset-password', const {});
    lastGeneratedPassword = response['temporaryPassword'] as String?;
    return getBusinessById(id);
  }

  /// The password produced by the most recent [resetBusinessPassword]. Read it
  /// immediately — the next reset replaces it, and nothing else holds it.
  String? lastGeneratedPassword;

  @override
  Future<List<SystemActivityEntry>> recentActivity() async {
    final result = await _client.getList('/admin/activity?limit=20');
    return result.data
        .cast<Map<String, dynamic>>()
        .map((row) => SystemActivityEntry(
              description: (row['description'] as String?) ?? (row['action'] as String?) ?? '',
              businessName: (row['businessName'] as String?) ?? 'Platform',
              timestamp: DateTime.tryParse('${row['createdAt']}') ?? DateTime.now(),
            ))
        .toList();
  }
}
