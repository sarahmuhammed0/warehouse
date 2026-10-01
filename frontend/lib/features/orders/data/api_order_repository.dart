import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'order_models.dart';
import 'order_repository.dart';

/// Orders and Sales against the real backend (§13/§14/§43).
///
/// One endpoint serves both screens, because the backend keeps both in one
/// `orders` table with an `order_type` flag — the same decision this module's
/// models already record.
class ApiOrderRepository implements OrderRepository {
  ApiOrderRepository(this._client);

  final ApiClient _client;

  static const _statusNames = {
    OrderStatus.draft: 'draft',
    OrderStatus.pending: 'pending',
    OrderStatus.confirmed: 'confirmed',
    OrderStatus.processing: 'processing',
    OrderStatus.ready: 'ready',
    OrderStatus.completed: 'completed',
    OrderStatus.cancelled: 'cancelled',
    OrderStatus.returned: 'returned',
    OrderStatus.partiallyReturned: 'partially_returned',
  };

  static OrderStatus _statusFrom(String? wire) {
    for (final entry in _statusNames.entries) {
      if (entry.value == wire) return entry.key;
    }
    return OrderStatus.draft;
  }

  static const _methodNames = {
    PaymentMethod.cash: 'cash',
    PaymentMethod.bankTransfer: 'bank_transfer',
    PaymentMethod.card: 'card',
    PaymentMethod.other: 'other',
  };

  static PaymentMethod _methodFrom(String? wire) {
    for (final entry in _methodNames.entries) {
      if (entry.value == wire) return entry.key;
    }
    return PaymentMethod.cash;
  }

  static OrderLineItem _itemFrom(Map<String, dynamic> json) => OrderLineItem(
    productId: '${json['productId']}',
    productName: (json['productName'] as String?) ?? '',
    // §55's snapshot: the name and price as they were when the line was
    // written, which is what the server sends back.
    quantity: (json['quantity'] as num?)?.round() ?? 0,
    unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    discount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
    tax: (json['taxAmount'] as num?)?.toDouble() ?? 0,
  );

  Order _fromJson(Map<String, dynamic> json, {List<OrderLineItem> items = const []}) {
    final payments = (json['payments'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
    return Order(
      id: '${json['id']}',
      // The tenant is implied by the session, so the server does not repeat it
      // on every row. Screens use it only to group a System Admin's drill-down,
      // which passes the id it already has.
      businessId: '${json['businessId'] ?? ''}',
      orderNumber: (json['orderNumber'] as String?) ?? '',
      orderType: (json['orderType'] as String?) == 'quick_sale' ? OrderType.quickSale : OrderType.standard,
      customerId: json['customerId'] == null ? null : '${json['customerId']}',
      customerName: json['customerName'] as String?,
      items: items,
      // NOTE: the server also supports an order-level discount, which this
      // model has no field for — §43's discount is per line in this UI. An
      // order given one through the API will therefore show its lines' own
      // arithmetic rather than the server's lower total. Representing it needs
      // a model field and a row on the screen, so it is left visible here
      // rather than folded into extraCharges, which would display a negative
      // charge and be a lie.
      extraCharges: (json['extraCharges'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
      // The order row carries no payment method — §43 records a method per
      // payment, because an order can be settled partly in cash and partly by
      // transfer. The most recent one is what the detail screen shows.
      paymentMethod: payments == null || payments.isEmpty
          ? PaymentMethod.cash
          : _methodFrom(payments.first['method'] as String?),
      status: _statusFrom(json['status'] as String?),
      notes: json['notes'] as String?,
      createdBy: (json['createdByName'] as String?) ?? '',
      createdAt: DateTime.tryParse('${json['orderDate'] ?? json['createdAt']}') ?? DateTime.now(),
    );
  }

  @override
  Future<PaginatedResult<Order>> list(PagedQuery query) async {
    final result = await _client.getList('/orders?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      // The list endpoint does not carry line items — a page of orders with
      // every line would be a much larger response for a table that shows
      // totals. The detail screen reads them with `getById`.
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<Order> getById(String id) async {
    final json = await _client.getJson('/orders/$id');
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((row) => _itemFrom(row as Map<String, dynamic>))
        .toList();
    return _fromJson(json, items: items);
  }

  @override
  Future<Order> create(OrderDraft draft) async {
    // A quick sale is born with its goods gone (§13): the customer is standing
    // there. `confirmed` is the status at which the backend moves stock, so
    // that is what a quick sale is created as — and it is then closed, which is
    // what this module's models mean by "born Completed".
    final isQuickSale = draft.orderType == OrderType.quickSale;

    final created = await _client.postJson('/orders', {
      'orderType': isQuickSale ? 'quick_sale' : 'standard',
      'customerId': draft.customerId == null ? null : int.tryParse(draft.customerId!),
      'items': [
        for (final item in draft.items)
          {
            'productId': int.tryParse(item.productId),
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'discountAmount': item.discount,
            // An amount, not a rate — the form collects the tax per line.
            'taxAmount': item.tax,
          },
      ],
      'extraCharges': draft.extraCharges,
      'notes': draft.notes,
      'status': isQuickSale ? 'confirmed' : 'draft',
    });

    final id = '${created['id']}';

    // §43: the money the customer handed over, as its own record with its own
    // method, rather than a column on the order.
    if (draft.paidAmount > 0) {
      await _client.postJson('/orders/$id/payments', {
        'amount': draft.paidAmount,
        'method': _methodNames[draft.paymentMethod] ?? 'cash',
      });
    }

    if (isQuickSale) {
      await _client.patchJson('/orders/$id/status', {'status': 'completed'});
    }

    return getById(id);
  }

  @override
  Future<Order> updateStatus(String id, OrderStatus status) async {
    await _client.patchJson('/orders/$id/status', {
      'status': _statusNames[status] ?? 'draft',
      // §17 requires a reason for a cancellation. The screen confirms the
      // action but collects no text, so this records where it came from rather
      // than failing the request — a reason box is a UI change.
      if (status == OrderStatus.cancelled) 'reason': 'Cancelled from the order screen',
    });
    return getById(id);
  }

  @override
  Future<List<Order>> listForBusiness(String businessId, {OrderType? type}) async {
    // §57's System Admin drill-down, through the admin endpoint that names the
    // business — a business-side route is scoped to the caller's own session
    // (§36), which is the isolation this cannot be allowed to weaken.
    //
    // The rows carry their line items, because this model computes an order's
    // total from its lines. Without them every order would read as 0.00, which
    // is worse than unknown: it looks like a real figure.
    final typeParam = switch (type) {
      OrderType.quickSale => '?type=quick_sale',
      OrderType.standard => '?type=standard',
      null => '',
    };
    final response = await _client.getJson('/admin/businesses/$businessId/orders$typeParam');
    return ((response['items'] as List<dynamic>?) ?? const []).map((row) {
      final json = row as Map<String, dynamic>;
      final items = ((json['items'] as List<dynamic>?) ?? const [])
          .map((item) => _itemFrom(item as Map<String, dynamic>))
          .toList();
      return _fromJson(json, items: items);
    }).toList();
  }

  /// §28's invoice. Bytes, not JSON — so this goes through the Dio instance
  /// directly rather than [ApiClient]'s envelope unwrapping, which would try
  /// to read a PDF as a success/error object.
  ///
  /// The session's Authorization header is attached by the interceptor on that
  /// same instance, which is why the file cannot simply be opened as a link:
  /// the endpoint is gated on orders.view like the order itself.
  @override
  Future<Uint8List> invoicePdf(String id) async {
    final response = await _client.dio.get<List<int>>(
      '/orders//pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  }
}
