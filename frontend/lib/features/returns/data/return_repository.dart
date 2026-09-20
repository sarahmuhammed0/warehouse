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
  LocalReturnRepository() {
    _seed();
  }

  final List<ProductReturn> _items = [];
  int _nextNumber = 1;
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      ProductReturn(
        id: 'ret-${_nextId++}',
        returnNumber: 'RET-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        orderId: 'ord-1',
        orderNumber: 'ORD-2026-000001',
        customerName: 'Ahmed Al-Rashid',
        items: const [ReturnLineItem(productId: 'prod-2', productName: '3-Seat Sofa — Beige', quantity: 1, condition: ItemCondition.damaged)],
        reason: 'Wrong color delivered',
        refundAmount: 420,
        status: ReturnStatus.requested,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      ProductReturn(
        id: 'ret-${_nextId++}',
        returnNumber: 'RET-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        orderId: 'ord-3',
        orderNumber: 'ORD-2026-000003',
        customerName: 'Karwan Furniture Retail',
        items: const [ReturnLineItem(productId: 'prod-5', productName: 'Office Desk — Standard', quantity: 2, condition: ItemCondition.sellable)],
        reason: 'Customer changed mind',
        refundAmount: 290,
        status: ReturnStatus.approved,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      ProductReturn(
        id: 'ret-${_nextId++}',
        returnNumber: 'RET-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        orderId: 'ord-2',
        orderNumber: 'SALE-2026-000001',
        customerName: null,
        items: const [ReturnLineItem(productId: 'prod-6', productName: 'Ergonomic Office Chair', quantity: 1, condition: ItemCondition.sellable)],
        reason: 'Defective part',
        refundAmount: 110,
        status: ReturnStatus.completed,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      ProductReturn(
        id: 'ret-${_nextId++}',
        returnNumber: 'RET-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        orderId: 'ord-1',
        orderNumber: 'ORD-2026-000001',
        customerName: 'Ahmed Al-Rashid',
        items: const [ReturnLineItem(productId: 'prod-1', productName: '3-Seat Sofa — Charcoal', quantity: 1, condition: ItemCondition.damaged)],
        reason: 'Damaged in transit',
        refundAmount: 420,
        status: ReturnStatus.rejected,
        notes: 'Damage occurred after delivery, outside return policy',
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ]);
  }

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
