import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'return_models.dart';
import 'return_repository.dart';

/// Returns against the real backend (§16).
///
/// Satisfies the same [ReturnRepository] interface as the demo version, so no
/// screen changes when this replaces it.
class ApiReturnRepository implements ReturnRepository {
  ApiReturnRepository(this._client);

  final ApiClient _client;

  static const _statusNames = {
    ReturnStatus.requested: 'requested',
    ReturnStatus.approved: 'approved',
    ReturnStatus.rejected: 'rejected',
    ReturnStatus.completed: 'completed',
  };

  static ReturnStatus _statusFrom(String? wire) {
    for (final entry in _statusNames.entries) {
      if (entry.value == wire) return entry.key;
    }
    return ReturnStatus.requested;
  }

  static ReturnLineItem _itemFrom(Map<String, dynamic> json) => ReturnLineItem(
    productId: '${json['productId']}',
    productName: (json['productName'] as String?) ?? '',
    quantity: (json['quantity'] as num?)?.round() ?? 0,
    condition: (json['condition'] as String?) == 'damaged' ? ItemCondition.damaged : ItemCondition.sellable,
  );

  ProductReturn _fromJson(Map<String, dynamic> json, {List<ReturnLineItem> items = const []}) => ProductReturn(
    id: '${json['id']}',
    returnNumber: (json['returnNumber'] as String?) ?? '',
    orderId: '${json['orderId']}',
    orderNumber: (json['orderNumber'] as String?) ?? '',
    customerName: json['customerName'] as String?,
    items: items,
    reason: (json['reason'] as String?) ?? '',
    refundAmount: (json['refundAmount'] as num?)?.toDouble() ?? 0,
    status: _statusFrom(json['status'] as String?),
    notes: json['note'] as String?,
    requestedBy: (json['createdByName'] as String?) ?? '',
    createdAt: DateTime.tryParse('${json['returnDate'] ?? json['createdAt']}') ?? DateTime.now(),
  );

  @override
  Future<PaginatedResult<ProductReturn>> list(PagedQuery query) async {
    final result = await _client.getList('/returns?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<ProductReturn> getById(String id) async {
    final json = await _client.getJson('/returns/$id');
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((row) => _itemFrom(row as Map<String, dynamic>))
        .toList();
    return _fromJson(json, items: items);
  }

  @override
  Future<ProductReturn> create(ReturnDraft draft) async {
    // A return names an order LINE, because the same product can appear twice
    // on one order at two prices and the refund has to know which. This
    // module's models carry only the product, so the line is resolved from the
    // order's own returnable lines — which is also where the server says how
    // much of each is left.
    //
    // Where a product genuinely appears on two lines, the first line with
    // enough left is taken. That is a real ambiguity rather than a safe
    // default, and the honest fix is a line id on the model — a change to the
    // return form, not to this repository. The server still validates the
    // quantity, so the worst case is a refund priced from the wrong line of the
    // same product, never more than was paid.
    final returnable = await _client.getJson('/orders/${draft.orderId}/returnable');
    final lines = (returnable['lines'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

    final claimed = <String, num>{};
    final items = <Map<String, dynamic>>[];

    for (final item in draft.items) {
      final candidates = lines.where((line) => '${line['productId']}' == item.productId);
      if (candidates.isEmpty) {
        throw StateError('"${item.productName}" is not on that order.');
      }
      final line = candidates.firstWhere(
        (candidate) {
          final remaining = (candidate['remaining'] as num? ?? 0) - (claimed['${candidate['id']}'] ?? 0);
          return remaining >= item.quantity;
        },
        orElse: () => candidates.first,
      );
      claimed['${line['id']}'] = (claimed['${line['id']}'] ?? 0) + item.quantity;

      items.add({
        'orderItemId': line['id'],
        'quantity': item.quantity,
        'condition': item.condition == ItemCondition.damaged ? 'damaged' : 'sellable',
      });
    }

    final created = await _client.postJson('/returns', {
      'orderId': int.tryParse(draft.orderId),
      'items': items,
      'reason': draft.reason,
      // Sent, so the amount the operator agreed is the amount recorded. The
      // server caps it at what was actually paid for those quantities.
      'refundAmount': draft.refundAmount,
      'note': draft.notes,
    });

    return getById('${created['id']}');
  }

  @override
  Future<ProductReturn> updateStatus(String id, ReturnStatus status) async {
    await _client.patchJson('/returns/$id/status', {'status': _statusNames[status] ?? 'requested'});
    return getById(id);
  }
}
