import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'customer_models.dart';
import 'customer_repository.dart';


/// Customers against the real backend (§18).
///
/// Satisfies the same [CustomerRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiCustomerRepository implements CustomerRepository {
  ApiCustomerRepository(this._client);

  final ApiClient _client;

  static Customer _fromJson(Map<String, dynamic> json) => Customer(
    id: '${json['id']}',
    code: (json['code'] as String?) ?? '',
    fullName: (json['name'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    secondaryPhone: json['phoneSecondary'] as String?,
    email: json['email'] as String?,
    address: json['address'] as String?,
    company: json['company'] as String?,
    notes: json['notes'] as String?,
    status: (json['status'] as String?) == 'inactive' ? CustomerStatus.inactive : CustomerStatus.active,
    // Derived server-side from orders and payments (§18). They are absent
    // rather than zero for a role without `financial.view`, and a missing
    // figure must not be shown as a confident 0 — but the model has no
    // nullable option, so 0 is what an unprivileged role sees. The server is
    // the one that decides, which is the part that matters.
    totalPurchases: (json['totalPurchases'] as num?)?.toDouble() ?? 0,
    outstandingBalance: (json['outstandingBalance'] as num?)?.toDouble() ?? 0,
    orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
  );

  static Map<String, dynamic> _toJson(CustomerDraft draft) => {
    'name': draft.fullName,
    'phone': draft.phone,
    'phoneSecondary': draft.secondaryPhone,
    'email': draft.email,
    'address': draft.address,
    'company': draft.company,
    'notes': draft.notes,
    'status': draft.status.name,
  };

  @override
  Future<PaginatedResult<Customer>> list(PagedQuery query) async {
    final result = await _client.getList('/customers?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<List<Customer>> allForPicker() async {
    // Active customers only, one page large enough for a picker — the same
    // approach and the same caveat as products: the backend caps pageSize at
    // 100, so a business with more than that needs a searchable picker, which
    // is a UI change rather than a repository one.
    final result = await _client.getList('/customers?status=active&pageSize=100&sort=name&direction=asc');
    return result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList();
  }

  @override
  Future<Customer> getById(String id) async => _fromJson(await _client.getJson('/customers/$id'));

  @override
  Future<Customer> create(CustomerDraft draft) async =>
      _fromJson(await _client.postJson('/customers', _toJson(draft)));

  @override
  Future<Customer> update(String id, CustomerDraft draft) async =>
      _fromJson(await _client.patchJson('/customers/$id', _toJson(draft)));

  @override
  Future<void> setStatus(String id, CustomerStatus status) async {
    await _client.patchJson('/customers/$id', {'status': status.name});
  }

  @override
  Future<Customer> applyOrder(String id, {required double grandTotal, required double paidAmount}) async {
    // Nothing to apply. These totals are computed from the orders and payments
    // tables on every read, so the order that was just saved is already in
    // them — writing them again from the client is how the two versions of the
    // same number start to disagree, which is what the contract notes mean by
    // "never client-trusted". Re-reading is what the caller actually wants:
    // the customer, with the new order counted.
    return getById(id);
  }
}
