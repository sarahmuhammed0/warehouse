import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'purchase_models.dart';
import 'purchase_repository.dart';

/// Purchases against the real backend (§20).
///
/// Satisfies the same [PurchaseRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiPurchaseRepository implements PurchaseRepository {
  ApiPurchaseRepository(this._client);

  final ApiClient _client;

  /// The backend also has a `draft` status, which this module's three-value
  /// enum does not — a draft purchase reads as pending here, which is what it
  /// is from the warehouse's point of view: recorded, not yet received.
  static PurchaseStatus _statusFrom(String? wire) => switch (wire) {
    'completed' => PurchaseStatus.completed,
    'cancelled' => PurchaseStatus.cancelled,
    _ => PurchaseStatus.pending,
  };

  static const _statusNames = {
    PurchaseStatus.pending: 'pending',
    PurchaseStatus.completed: 'completed',
    PurchaseStatus.cancelled: 'cancelled',
  };

  static PurchaseLineItem _itemFrom(Map<String, dynamic> json) => PurchaseLineItem(
    productId: '${json['productId']}',
    productName: (json['productName'] as String?) ?? '',
    quantity: (json['quantity'] as num?)?.round() ?? 0,
    unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0,
    discount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
    tax: (json['taxAmount'] as num?)?.toDouble() ?? 0,
  );

  Purchase _fromJson(Map<String, dynamic> json, {List<PurchaseLineItem> items = const []}) {
    final payments = (json['payments'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    return Purchase(
      id: '${json['id']}',
      purchaseNumber: (json['purchaseNumber'] as String?) ?? '',
      supplierId: json['supplierId'] == null ? '' : '${json['supplierId']}',
      supplierName: (json['supplierName'] as String?) ?? '',
      items: items,
      paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
      // §43 records a method per payment, not one on the document. The first —
      // most recent — is what the detail screen shows.
      paymentMethod: payments == null || payments.isEmpty
          ? 'Cash'
          : _methodLabel(payments.first['method'] as String?),
      status: _statusFrom(json['status'] as String?),
      notes: json['note'] as String?,
      createdBy: (json['createdByName'] as String?) ?? '',
      createdAt: DateTime.tryParse('${json['purchaseDate'] ?? json['createdAt']}') ?? DateTime.now(),
    );
  }

  /// The demo data used these words, so the screens already read this way.
  static String _methodLabel(String? wire) => switch (wire) {
    'bank_transfer' => 'Bank transfer',
    'card' => 'Card',
    'other' => 'Other',
    _ => 'Cash',
  };

  static String _methodWire(String label) => switch (label.toLowerCase()) {
    'bank transfer' => 'bank_transfer',
    'card' => 'card',
    'other' => 'other',
    _ => 'cash',
  };

  @override
  Future<PaginatedResult<Purchase>> list(PagedQuery query) async {
    final result = await _client.getList('/purchases?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<Purchase> getById(String id) async {
    final json = await _client.getJson('/purchases/$id');
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((row) => _itemFrom(row as Map<String, dynamic>))
        .toList();
    return _fromJson(json, items: items);
  }

  @override
  Future<Purchase> create(PurchaseDraft draft) async {
    final created = await _client.postJson('/purchases', {
      'supplierId': int.tryParse(draft.supplierId),
      'items': [
        for (final item in draft.items)
          {
            'productId': int.tryParse(item.productId),
            'quantity': item.quantity,
            'unitCost': item.unitCost,
            'discountAmount': item.discount,
            'taxAmount': item.tax,
          },
      ],
      // §20's flow: recorded now, received when it arrives. The backend
      // defaults to pending, which is what the form means.
      'paidAmount': draft.paidAmount,
      'paymentMethod': _methodWire(draft.paymentMethod),
      'note': draft.notes,
    });
    return getById('${created['id']}');
  }

  @override
  Future<Purchase> updateStatus(String id, PurchaseStatus status) async {
    await _client.patchJson('/purchases/$id/status', {'status': _statusNames[status] ?? 'pending'});
    return getById(id);
  }
}
