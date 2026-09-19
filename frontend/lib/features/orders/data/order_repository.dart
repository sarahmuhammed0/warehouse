import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'order_models.dart';

abstract class OrderRepository {
  Future<PaginatedResult<Order>> list(PagedQuery query);
  Future<Order> getById(String id);
  Future<Order> create(OrderDraft draft);
  Future<Order> updateStatus(String id, OrderStatus status);
}

class LocalOrderRepository with DemoRepository implements OrderRepository {
  LocalOrderRepository() {
    _seed();
  }

  final List<Order> _items = [];
  int _nextOrderNumber = 1;
  int _nextId = 1;

  String _newOrderNumber(OrderType type) {
    final prefix = type == OrderType.quickSale ? 'SALE' : 'ORD';
    return '$prefix-2026-${(_nextOrderNumber++).toString().padLeft(6, '0')}';
  }

  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      Order(
        id: 'ord-${_nextId++}',
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-1',
        customerName: 'Ahmed Al-Rashid',
        items: const [
          OrderLineItem(productId: 'prod-1', productName: '3-Seat Sofa — Charcoal', quantity: 2, unitPrice: 420, tax: 42),
        ],
        extraCharges: 0,
        paidAmount: 500,
        paymentMethod: PaymentMethod.bankTransfer,
        status: OrderStatus.processing,
        createdBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        orderNumber: _newOrderNumber(OrderType.quickSale),
        orderType: OrderType.quickSale,
        customerId: null,
        customerName: null,
        items: const [
          OrderLineItem(productId: 'prod-6', productName: 'Ergonomic Office Chair', quantity: 1, unitPrice: 110, tax: 5.5),
        ],
        extraCharges: 0,
        paidAmount: 115.5,
        paymentMethod: PaymentMethod.cash,
        status: OrderStatus.completed,
        createdBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-3',
        customerName: 'Karwan Furniture Retail',
        items: const [
          OrderLineItem(productId: 'prod-5', productName: 'Office Desk — Standard', quantity: 10, unitPrice: 145, discount: 100, tax: 145),
        ],
        extraCharges: 50,
        paidAmount: 0,
        paymentMethod: PaymentMethod.other,
        status: OrderStatus.pending,
        createdBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
    ]);
  }

  @override
  Future<PaginatedResult<Order>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Order>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final type = query.filters['orderType'] as OrderType?;
    if (type != null) pool = pool.where((o) => o.orderType == type).toList();
    final status = query.filters['status'] as OrderStatus?;
    if (status != null) pool = pool.where((o) => o.status == status).toList();
    return paginateInMemory<Order>(
      pool,
      query,
      matches: (item, q) => item.orderNumber.toLowerCase().contains(q) || (item.customerName?.toLowerCase().contains(q) ?? false),
    );
  }

  @override
  Future<Order> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((o) => o.id == id, orElse: () => throw StateError('Order not found'));
  }

  @override
  Future<Order> create(OrderDraft draft) async {
    await simulatedLatency();
    final created = Order(
      id: 'ord-${_nextId++}',
      orderNumber: _newOrderNumber(draft.orderType),
      orderType: draft.orderType,
      customerId: draft.customerId,
      customerName: draft.customerName,
      items: [for (final i in draft.items) i.asLineItem()],
      extraCharges: draft.extraCharges,
      paidAmount: draft.paidAmount,
      paymentMethod: draft.paymentMethod,
      status: draft.orderType == OrderType.quickSale ? OrderStatus.completed : OrderStatus.draft,
      notes: draft.notes,
      createdBy: 'Demo Admin',
      createdAt: DateTime.now(),
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<Order> updateStatus(String id, OrderStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((o) => o.id == id);
    if (index == -1) throw StateError('Order not found');
    final existing = _items[index];
    if (!existing.allowedNextStatuses.contains(status)) {
      throw StateError('Illegal status transition');
    }
    final updated = Order(
      id: existing.id,
      orderNumber: existing.orderNumber,
      orderType: existing.orderType,
      customerId: existing.customerId,
      customerName: existing.customerName,
      items: existing.items,
      extraCharges: existing.extraCharges,
      paidAmount: existing.paidAmount,
      paymentMethod: existing.paymentMethod,
      status: status,
      notes: existing.notes,
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
    );
    _items[index] = updated;
    return updated;
  }
}

extension _OrderItemDraftLineItem on OrderItemDraft {
  OrderLineItem asLineItem() => OrderLineItem(
        productId: productId,
        productName: productName,
        quantity: quantity,
        unitPrice: unitPrice,
        discount: discount,
        tax: tax,
      );
}
