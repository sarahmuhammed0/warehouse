import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'return_models.dart';

abstract class ReturnRepository {
  Future<PaginatedResult<ProductReturn>> list(PagedQuery query);
  Future<ProductReturn> getById(String id);
  Future<ProductReturn> create(ReturnDraft draft);
  Future<ProductReturn> updateStatus(String id, ReturnStatus status);
}

class LocalReturnRepository with DemoRepository implements ReturnRepository {
  final List<ProductReturn> _items = [];
  int _nextNumber = 1;
  int _nextId = 1;

  @override
  Future<PaginatedResult<ProductReturn>> list(PagedQuery query) async {
    await simulatedLatency();
    final pool = List<ProductReturn>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return paginateInMemory<ProductReturn>(pool, query, matches: (item, q) => item.returnNumber.toLowerCase().contains(q) || item.orderNumber.toLowerCase().contains(q));
  }

  @override
  Future<ProductReturn> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((r) => r.id == id, orElse: () => throw StateError('Return not found'));
  }

  @override
  Future<ProductReturn> create(ReturnDraft draft) async {
    await simulatedLatency();
    final created = ProductReturn(
      id: 'ret-${_nextId++}',
      returnNumber: 'RET-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
      orderId: draft.orderId,
      orderNumber: draft.orderNumber,
      customerName: draft.customerName,
      items: [for (final i in draft.items) ReturnLineItem(productId: i.productId, productName: i.productName, quantity: i.quantity, condition: i.condition)],
      reason: draft.reason,
      refundAmount: draft.refundAmount,
      status: ReturnStatus.requested,
      notes: draft.notes,
      requestedBy: 'Demo Admin',
      createdAt: DateTime.now(),
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<ProductReturn> updateStatus(String id, ReturnStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((r) => r.id == id);
    if (index == -1) throw StateError('Return not found');
    final existing = _items[index];
    final updated = ProductReturn(
      id: existing.id,
      returnNumber: existing.returnNumber,
      orderId: existing.orderId,
      orderNumber: existing.orderNumber,
      customerName: existing.customerName,
      items: existing.items,
      reason: existing.reason,
      refundAmount: existing.refundAmount,
      status: status,
      notes: existing.notes,
      requestedBy: existing.requestedBy,
      createdAt: existing.createdAt,
    );
    _items[index] = updated;
    return updated;
  }
}
