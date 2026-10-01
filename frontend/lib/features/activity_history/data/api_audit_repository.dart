import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'audit_models.dart';
import 'audit_repository.dart';

/// The activity trail (§30) against the real backend.
///
/// Read-only, because the endpoint is: rows are written by the trail
/// middleware as a side effect of the action they describe. Evidence a client
/// can add to is not evidence.
class ApiAuditRepository implements AuditRepository {
  ApiAuditRepository(this._client);

  final ApiClient _client;

  static AuditLogEntry _fromJson(Map<String, dynamic> json) => AuditLogEntry(
    id: '${json['id']}',
    // A public self-registration has no actor by design. "System" is the
    // truthful label for it — an empty name would read as a record whose
    // author was lost, which is the one thing a trail must not suggest.
    userName: (json['actorName'] as String?) ?? 'System',
    action: (json['action'] as String?) ?? '',
    module: (json['module'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    ipAddress: json['ipAddress'] as String?,
    referenceId: json['referenceId'] == null ? null : '${json['referenceId']}',
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
  );

  @override
  Future<PaginatedResult<AuditLogEntry>> list(PagedQuery query) async {
    final params = <String>[
      buildListQuery(query),
      // The screen filters by module and by who did it; the server takes both.
      if (query.filters['module'] != null) 'module=${query.filters['module']}',
      if (query.filters['action'] != null) 'action=${query.filters['action']}',
    ];
    final result = await _client.getList('/audit-logs?${params.join('&')}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }
}
