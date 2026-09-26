import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import 'category_models.dart';
import 'category_repository.dart';

/// Categories against the real backend (§7).
///
/// Satisfies the same [CategoryRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiCategoryRepository implements CategoryRepository {
  ApiCategoryRepository(this._client);

  final ApiClient _client;

  static Category _fromJson(Map<String, dynamic> json) => Category(
    id: '${json['id']}',
    name: (json['name'] as String?) ?? '',
    code: (json['code'] as String?) ?? '',
    description: json['description'] as String?,
    imageUrl: json['imageUrl'] as String?,
    parentId: json['parentId'] == null ? null : '${json['parentId']}',
    parentName: json['parentName'] as String?,
    status: (json['status'] as String?) == 'inactive' ? CategoryStatus.inactive : CategoryStatus.active,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    // Derived server-side from the products table, never stored.
    productCount: (json['productCount'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
  );

  static Map<String, dynamic> _toJson(CategoryDraft draft) => {
    'name': draft.name,
    'code': draft.code,
    'description': draft.description,
    'imageUrl': draft.imageUrl,
    // Sent even when null: clearing a parent (making a subcategory
    // top-level) is a real edit, and omitting the key would leave it be.
    'parentId': draft.parentId == null ? null : int.tryParse(draft.parentId!),
    'sortOrder': draft.sortOrder,
    'status': draft.status.name,
  };

  @override
  Future<PaginatedResult<Category>> list(PagedQuery query) async {
    final result = await _client.getList('/categories?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<List<Category>> allForPicker() async {
    // A dedicated endpoint rather than list(pageSize: huge): the picker
    // needs every active category, and paging it would silently truncate.
    final result = await _client.getList('/categories/options');
    return result.data
        .map(
          (row) => Category(
            id: '${(row as Map<String, dynamic>)['id']}',
            name: (row['name'] as String?) ?? '',
            code: '',
            parentId: row['parentId'] == null ? null : '${row['parentId']}',
            status: CategoryStatus.active,
            sortOrder: 0,
            productCount: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<Category> getById(String id) async => _fromJson(await _client.getJson('/categories/$id'));

  @override
  Future<Category> create(CategoryDraft draft) async =>
      _fromJson(await _client.postJson('/categories', _toJson(draft)));

  @override
  Future<Category> update(String id, CategoryDraft draft) async =>
      _fromJson(await _client.patchJson('/categories/$id', _toJson(draft)));

  @override
  Future<void> setStatus(String id, CategoryStatus status) async {
    await _client.patchJson('/categories/$id', {'status': status.name});
  }
}

/// The query string every list endpoint accepts. Shared so a filter name
/// cannot mean one thing in one module and something else in another.
String buildListQuery(PagedQuery query) {
  final params = <String, String>{
    'page': '${query.page}',
    'pageSize': '${query.pageSize}',
    if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
    'sort': ?query.sortField,
    if (query.sortField != null) 'direction': query.sortAscending ? 'asc' : 'desc',
  };
  for (final entry in query.filters.entries) {
    final value = entry.value;
    if (value == null || '$value'.isEmpty) continue;
    params[entry.key] = '$value';
  }
  return params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
}
