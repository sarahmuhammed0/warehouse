import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'customer_models.dart';

abstract class CustomerRepository {
  Future<PaginatedResult<Customer>> list(PagedQuery query);
  Future<Customer> getById(String id);
  Future<List<Customer>> allForPicker();
  Future<Customer> create(CustomerDraft draft);
  Future<Customer> update(String id, CustomerDraft draft);
  Future<void> setStatus(String id, CustomerStatus status);

  /// Rolls one order into this customer's running totals.
  ///
  /// `totalPurchases`, `outstandingBalance` and `orderCount` were seeded
  /// values that nothing ever changed: a customer you created started at
  /// zero and stayed there no matter how many orders you placed for them,
  /// so the Customers table and the detail screen's stat cards were
  /// permanently wrong for every non-seeded customer. Server-computed in a
  /// real deployment (see the contract notes' "never client-trusted"
  /// caveat); computed here so the demo tells the truth.
  Future<Customer> applyOrder(String id, {required double grandTotal, required double paidAmount});
}

class LocalCustomerRepository with DemoRepository implements CustomerRepository {
  LocalCustomerRepository() {
    _seed();
  }

  final List<Customer> _items = [];
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    final seedData = [
      ('Ahmed Al-Rashid', '+9647701112233', 'Al-Rashid Trading Co.', 4200.0, 300.0, 6),
      ('Layla Hassan', '+9647709998877', null, 850.0, 0.0, 2),
      ('Karwan Furniture Retail', '+9647701234500', 'Karwan Retail LLC', 15600.0, 1200.0, 14),
      ('Sara Mahmoud', '+9647705556677', null, 210.0, 0.0, 1),
      ('Baghdad Office Supplies', '+9647801122334', 'Baghdad Office Supplies', 9800.0, 0.0, 9),
    ];
    for (final (name, phone, company, total, balance, orders) in seedData) {
      _items.add(
        Customer(
          id: 'cust-${_nextId++}',
          code: 'CUST-${_nextId.toString().padLeft(4, '0')}',
          fullName: name,
          phone: phone,
          email: null,
          address: null,
          company: company,
          notes: null,
          status: CustomerStatus.active,
          totalPurchases: total,
          outstandingBalance: balance,
          orderCount: orders,
          createdAt: now,
        ),
      );
    }
  }

  @override
  Future<PaginatedResult<Customer>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Customer>.from(_items);
    final status = query.filters['status'] as CustomerStatus?;
    if (status != null) pool = pool.where((c) => c.status == status).toList();
    return paginateInMemory<Customer>(
      pool,
      query,
      matches: (item, q) => item.fullName.toLowerCase().contains(q) || item.phone.contains(q) || item.code.toLowerCase().contains(q),
      sortKey: (item) => item.fullName,
    );
  }

  @override
  Future<Customer> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((c) => c.id == id, orElse: () => throw StateError('Customer not found'));
  }

  @override
  Future<List<Customer>> allForPicker() async {
    await simulatedLatency();
    return _items.where((c) => c.status == CustomerStatus.active).toList();
  }

  @override
  Future<Customer> create(CustomerDraft draft) async {
    await simulatedLatency();
    final created = Customer(
      id: 'cust-${_nextId++}',
      code: 'CUST-${_nextId.toString().padLeft(4, '0')}',
      fullName: draft.fullName,
      phone: draft.phone,
      secondaryPhone: draft.secondaryPhone,
      email: draft.email,
      address: draft.address,
      company: draft.company,
      notes: draft.notes,
      status: draft.status,
      totalPurchases: 0,
      outstandingBalance: 0,
      orderCount: 0,
      createdAt: DateTime.now(),
    );
    _items.add(created);
    return created;
  }

  @override
  Future<Customer> update(String id, CustomerDraft draft) async {
    await simulatedLatency();
    final index = _items.indexWhere((c) => c.id == id);
    if (index == -1) throw StateError('Customer not found');
    final existing = _items[index];
    final updated = Customer(
      id: existing.id,
      code: existing.code,
      fullName: draft.fullName,
      phone: draft.phone,
      secondaryPhone: draft.secondaryPhone,
      email: draft.email,
      address: draft.address,
      company: draft.company,
      notes: draft.notes,
      status: draft.status,
      totalPurchases: existing.totalPurchases,
      outstandingBalance: existing.outstandingBalance,
      orderCount: existing.orderCount,
      createdAt: existing.createdAt,
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<void> setStatus(String id, CustomerStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((c) => c.id == id);
    if (index == -1) throw StateError('Customer not found');
    final existing = _items[index];
    _items[index] = Customer(
      id: existing.id,
      code: existing.code,
      fullName: existing.fullName,
      phone: existing.phone,
      secondaryPhone: existing.secondaryPhone,
      email: existing.email,
      address: existing.address,
      company: existing.company,
      notes: existing.notes,
      status: status,
      totalPurchases: existing.totalPurchases,
      outstandingBalance: existing.outstandingBalance,
      orderCount: existing.orderCount,
      createdAt: existing.createdAt,
    );
  }

  @override
  Future<Customer> applyOrder(String id, {required double grandTotal, required double paidAmount}) async {
    await simulatedLatency();
    final index = _items.indexWhere((c) => c.id == id);
    if (index == -1) throw StateError('Customer not found');
    final existing = _items[index];
    final updated = Customer(
      id: existing.id,
      code: existing.code,
      fullName: existing.fullName,
      phone: existing.phone,
      secondaryPhone: existing.secondaryPhone,
      email: existing.email,
      address: existing.address,
      company: existing.company,
      notes: existing.notes,
      status: existing.status,
      totalPurchases: existing.totalPurchases + grandTotal,
      // What they still owe on this order. Never negative: overpaying is
      // not a credit balance in this model.
      outstandingBalance: existing.outstandingBalance + (grandTotal - paidAmount).clamp(0, double.infinity),
      orderCount: existing.orderCount + 1,
      createdAt: existing.createdAt,
    );
    _items[index] = updated;
    return updated;
  }
}
