import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'production_models.dart';
import 'production_repository.dart';

/// Production and the bill of materials against the real backend (§21/§22).
///
/// Satisfies the same [ProductionRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiProductionRepository implements ProductionRepository {
  ApiProductionRepository(this._client);

  final ApiClient _client;

  static const _statusNames = {
    ProductionStatus.planned: 'planned',
    ProductionStatus.inProgress: 'in_progress',
    ProductionStatus.completed: 'completed',
    ProductionStatus.cancelled: 'cancelled',
  };

  static ProductionStatus _statusFrom(String? wire) {
    for (final entry in _statusNames.entries) {
      if (entry.value == wire) return entry.key;
    }
    return ProductionStatus.planned;
  }

  /// A run's own material snapshot (§22) — what this batch needs, already
  /// multiplied out, never the per-unit recipe.
  static BomLine _materialFrom(Map<String, dynamic> json) => BomLine(
    materialProductId: '${json['materialProductId']}',
    materialProductName: (json['materialProductName'] as String?) ?? '',
    quantityRequired: (json['quantityRequired'] as num?)?.round() ?? 0,
    unit: (json['unitCode'] as String?) ?? (json['unitName'] as String?) ?? '',
  );

  /// A recipe line (§21) — per unit of the finished product.
  static BomLine _recipeFrom(Map<String, dynamic> json) => BomLine(
    materialProductId: '${json['materialProductId']}',
    materialProductName: (json['materialProductName'] as String?) ?? '',
    quantityRequired: (json['quantityPerUnit'] as num?)?.round() ?? 0,
    unit: (json['unitCode'] as String?) ?? (json['unitName'] as String?) ?? '',
  );

  ProductionOrder _fromJson(Map<String, dynamic> json, {List<BomLine> materials = const []}) => ProductionOrder(
    id: '${json['id']}',
    productionNumber: (json['productionNumber'] as String?) ?? '',
    productId: '${json['productId']}',
    productName: (json['productName'] as String?) ?? '',
    quantityPlanned: (json['quantityPlanned'] as num?)?.round() ?? 0,
    quantityProduced: (json['quantityProduced'] as num?)?.round() ?? 0,
    batchNumber: json['batchNumber'] as String?,
    materials: materials,
    // §22's cost tracking: an estimate while the run is planned, what the
    // batch actually cost once it is complete.
    cost: (json['productionCost'] as num?)?.toDouble() ?? 0,
    status: _statusFrom(json['status'] as String?),
    assignedTo: json['assignedUserName'] as String?,
    startedAt: json['startedAt'] == null ? null : DateTime.tryParse('${json['startedAt']}'),
    completedAt: json['completedAt'] == null ? null : DateTime.tryParse('${json['completedAt']}'),
    notes: json['note'] as String?,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
  );

  @override
  Future<PaginatedResult<ProductionOrder>> list(PagedQuery query) async {
    final result = await _client.getList('/production-orders?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<ProductionOrder> getById(String id) async {
    final json = await _client.getJson('/production-orders/$id');
    final materials = (json['materials'] as List<dynamic>? ?? const [])
        .map((row) => _materialFrom(row as Map<String, dynamic>))
        .toList();
    return _fromJson(json, materials: materials);
  }

  @override
  Future<ProductionOrder> create(ProductionDraft draft) async {
    final created = await _client.postJson('/production-orders', {
      'productId': int.tryParse(draft.productId),
      'quantityPlanned': draft.quantityPlanned,
      // The form has already scaled the recipe to the batch and lets the
      // operator adjust it, so the adjusted list is what the run records. Sent
      // only when there is one — otherwise the server takes the product's own
      // bill of materials, which is the same thing computed server-side.
      if (draft.materials.isNotEmpty)
        'materials': [
          for (final line in draft.materials)
            {
              'materialProductId': int.tryParse(line.materialProductId),
              'quantityRequired': line.quantityRequired,
            },
        ],
      'note': draft.notes,
    });
    return getById('${created['id']}');
  }

  @override
  Future<ProductionOrder> updateStatus(String id, ProductionStatus status) async {
    await _client.patchJson('/production-orders/$id/status', {
      'status': _statusNames[status] ?? 'planned',
    });
    return getById(id);
  }

  @override
  Future<List<BomLine>> bomFor(String productId) async {
    final json = await _client.getJson('/products/$productId/bom');
    return (json['lines'] as List<dynamic>? ?? const [])
        .map((row) => _recipeFrom(row as Map<String, dynamic>))
        .toList();
  }
}
