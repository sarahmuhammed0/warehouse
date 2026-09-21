import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_businesses.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'order_models.dart';

abstract class OrderRepository {
  Future<PaginatedResult<Order>> list(PagedQuery query);
  Future<Order> getById(String id);
  Future<Order> create(OrderDraft draft);
  Future<Order> updateStatus(String id, OrderStatus status);

  /// One tenant's orders, optionally narrowed to a single type — the
  /// System Admin's per-business Orders (standard) and Sales (quick sale)
  /// drill-downs, which mirror the two business-side modules exactly.
  /// See `ProductRepository.listForBusiness`'s note on why this is
  /// admin-only.
  Future<List<Order>> listForBusiness(String businessId, {OrderType? type});
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

  /// Every seeded order belongs to a tenant, and only ever references that
  /// tenant's own products — so the System Admin's per-business Orders and
  /// Sales drill-downs show internally consistent data, and their counts
  /// are the real record counts (see core/repositories/demo_businesses.dart).
  /// Standard orders feed the Orders module/overview; quick sales feed the
  /// Sales module/overview, exactly as the business-side split already works.
  void _seed() {
    final now = DateTime.now();
    _items.addAll([
      // ---- Karwan Furniture Factory: 2 orders + 1 sale ----
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessKarwan,
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
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessKarwan,
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-4',
        customerName: 'Sara Mahmoud',
        items: const [
          OrderLineItem(productId: 'prod-3', productName: 'Coffee Table — Oak', quantity: 3, unitPrice: 120, tax: 18),
        ],
        extraCharges: 0,
        paidAmount: 0,
        paymentMethod: PaymentMethod.other,
        status: OrderStatus.pending,
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessKarwan,
        orderNumber: _newOrderNumber(OrderType.quickSale),
        orderType: OrderType.quickSale,
        customerId: null,
        customerName: null,
        items: const [
          OrderLineItem(productId: 'prod-5', productName: 'Bookshelf — 5 Tier', quantity: 1, unitPrice: 95, tax: 4.75),
        ],
        extraCharges: 0,
        paidAmount: 99.75,
        paymentMethod: PaymentMethod.cash,
        status: OrderStatus.completed,
        createdBy: 'Dilan Omar',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),

      // ---- Erbil Central Warehouse: 2 orders + 1 sale ----
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessErbil,
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-3',
        customerName: 'Karwan Furniture Retail',
        items: const [
          OrderLineItem(productId: 'prod-11', productName: 'Office Desk — Standard', quantity: 10, unitPrice: 145, discount: 100, tax: 145),
        ],
        extraCharges: 50,
        paidAmount: 0,
        paymentMethod: PaymentMethod.other,
        status: OrderStatus.pending,
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessErbil,
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-1',
        customerName: 'Ahmed Al-Rashid',
        items: const [
          OrderLineItem(productId: 'prod-13', productName: 'Storage Shelving Unit', quantity: 4, unitPrice: 160, tax: 32),
        ],
        extraCharges: 0,
        paidAmount: 0,
        paymentMethod: PaymentMethod.other,
        status: OrderStatus.cancelled,
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessErbil,
        orderNumber: _newOrderNumber(OrderType.quickSale),
        orderType: OrderType.quickSale,
        customerId: null,
        customerName: null,
        items: const [
          OrderLineItem(productId: 'prod-12', productName: 'Ergonomic Office Chair', quantity: 1, unitPrice: 110, tax: 5.5),
        ],
        extraCharges: 0,
        paidAmount: 115.5,
        paymentMethod: PaymentMethod.cash,
        status: OrderStatus.completed,
        createdBy: 'Dilan Omar',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),

      // ---- City Storage Store: 1 order + 1 sale ----
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessCityStore,
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-2',
        customerName: 'Layla Hassan',
        items: const [
          OrderLineItem(productId: 'prod-15', productName: 'Queen Bed Frame', quantity: 1, unitPrice: 260, tax: 13),
        ],
        extraCharges: 0,
        paidAmount: 273,
        paymentMethod: PaymentMethod.card,
        status: OrderStatus.completed,
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessCityStore,
        orderNumber: _newOrderNumber(OrderType.quickSale),
        orderType: OrderType.quickSale,
        customerId: null,
        customerName: null,
        items: const [
          OrderLineItem(productId: 'prod-16', productName: 'Plastic Storage Bin (60L)', quantity: 4, unitPrice: 15, tax: 3),
        ],
        extraCharges: 0,
        paidAmount: 63,
        paymentMethod: PaymentMethod.cash,
        status: OrderStatus.returned,
        createdBy: 'Dilan Omar',
        createdAt: now.subtract(const Duration(days: 2)),
      ),

      // ---- Northern Distribution Center: 1 order + 1 sale ----
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessNorthern,
        orderNumber: _newOrderNumber(OrderType.standard),
        orderType: OrderType.standard,
        customerId: 'cust-3',
        customerName: 'Karwan Furniture Retail',
        items: const [
          OrderLineItem(productId: 'prod-18', productName: 'Shipping Carton (XL)', quantity: 100, unitPrice: 5, tax: 25),
        ],
        extraCharges: 0,
        paidAmount: 200,
        paymentMethod: PaymentMethod.bankTransfer,
        status: OrderStatus.processing,
        createdBy: 'Demo Owner',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      Order(
        id: 'ord-${_nextId++}',
        businessId: kDemoBusinessNorthern,
        orderNumber: _newOrderNumber(OrderType.quickSale),
        orderType: OrderType.quickSale,
        customerId: null,
        customerName: null,
        items: const [
          OrderLineItem(productId: 'prod-17', productName: 'Stretch Wrap Roll', quantity: 6, unitPrice: 18, tax: 5.4),
        ],
        extraCharges: 0,
        paidAmount: 113.4,
        paymentMethod: PaymentMethod.cash,
        status: OrderStatus.completed,
        createdBy: 'Dilan Omar',
        createdAt: now.subtract(const Duration(days: 6)),
      ),
    ]);
  }

  @override
  Future<List<Order>> listForBusiness(String businessId, {OrderType? type}) async {
    await simulatedLatency();
    return _items
        .where((o) => o.businessId == businessId && (type == null || o.orderType == type))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<PaginatedResult<Order>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Order>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final type = query.filters['orderType'] as OrderType?;
    if (type != null) pool = pool.where((o) => o.orderType == type).toList();
    final status = query.filters['status'] as OrderStatus?;
    if (status != null) pool = pool.where((o) => o.status == status).toList();
    // `period` backs the dashboard's "Today's sales"/"Today's orders" cards:
    // tapping a figure has to land on exactly the rows it counted, so the
    // same window that produced the number narrows the list.
    final period = query.filters['period'] as String?;
    if (period != null) {
      final now = DateTime.now();
      pool = pool.where((o) {
        return switch (period) {
          'today' => o.createdAt.year == now.year && o.createdAt.month == now.month && o.createdAt.day == now.day,
          'month' => o.createdAt.year == now.year && o.createdAt.month == now.month,
          _ => true,
        };
      }).toList();
    }
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
      businessId: kDemoBusinessForNewRecords,
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
      businessId: existing.businessId,
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
