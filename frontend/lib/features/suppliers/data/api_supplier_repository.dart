import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'supplier_models.dart';
import 'supplier_repository.dart';

/// Suppliers against the real backend (§19).
///
/// Satisfies the same [SupplierRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiSupplierRepository implements SupplierRepository {
  ApiSupplierRepository(this._client);

  final ApiClient _client;

  static Supplier _fromJson(Map<String, dynamic> json) => Supplier(
    id: '${json['id']}',
    name: (json['name'] as String?) ?? '',
    company: json['company'] as String?,
    phone: (json['phone'] as String?) ?? '',
    email: json['email'] as String?,
    address: json['address'] as String?,
    contactPerson: json['contactPerson'] as String?,
    notes: json['notes'] as String?,
    status: (json['status'] as String?) == 'inactive' ? SupplierStatus.inactive : SupplierStatus.active,
    // The server names this `totalPurchases` for both parties — for a supplier
    // it is what the business has bought FROM them, which is this field.
    // Derived from the purchases and payments tables, never stored (§19).
    totalPurchaseCost: (json['totalPurchases'] as num?)?.toDouble() ?? 0,
    outstandingBalance: (json['outstandingBalance'] as num?)?.toDouble() ?? 0,
    purchaseCount: (json['purchaseCount'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
  );

  static Map<String, dynamic> _toJson(SupplierDraft draft) => {
    'name': draft.name,
    'company': draft.company,
    'phone': draft.phone,
    'email': draft.email,
    'address': draft.address,
    'contactPerson': draft.contactPerson,
    'notes': draft.notes,
    'status': draft.status.name,
  };

  @override
  Future<PaginatedResult<Supplier>> list(PagedQuery query) async {
    final result = await _client.getList('/suppliers?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<List<Supplier>> allForPicker() async {
    final result = await _client.getList('/suppliers?status=active&pageSize=100&sort=name&direction=asc');
    return result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList();
  }

  @override
  Future<Supplier> getById(String id) async => _fromJson(await _client.getJson('/suppliers/$id'));

  @override
  Future<Supplier> create(SupplierDraft draft) async =>
      _fromJson(await _client.postJson('/suppliers', _toJson(draft)));

  @override
  Future<Supplier> update(String id, SupplierDraft draft) async =>
      _fromJson(await _client.patchJson('/suppliers/$id', _toJson(draft)));

  @override
  Future<void> setStatus(String id, SupplierStatus status) async {
    await _client.patchJson('/suppliers/$id', {'status': status.name});
  }
}
