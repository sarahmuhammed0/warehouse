import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'supplier_models.dart';

abstract class SupplierRepository {
  Future<PaginatedResult<Supplier>> list(PagedQuery query);
  Future<Supplier> getById(String id);
  Future<List<Supplier>> allForPicker();
  Future<Supplier> create(SupplierDraft draft);
  Future<Supplier> update(String id, SupplierDraft draft);
  Future<void> setStatus(String id, SupplierStatus status);
}

class LocalSupplierRepository with DemoRepository implements SupplierRepository {
  LocalSupplierRepository() {
    _seed();
  }

  final List<Supplier> _items = [];
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    final seed = [
      ('Erbil Timber Supply', 'Erbil Timber Co.', '+9647501112233', 28400.0, 2000.0, 22),
      ('Northern Textiles', 'Northern Textiles LLC', '+9647509998877', 15200.0, 0.0, 11),
      ('Steel & Fittings Co.', null, '+9647501234500', 9100.0, 500.0, 8),
      ('Gulf Foam Industries', 'Gulf Foam Industries', '+9750112233', 6300.0, 0.0, 5),
    ];
    for (final (name, company, phone, total, balance, count) in seed) {
      _items.add(
        Supplier(
          id: 'sup-${_nextId++}',
          name: name,
          company: company,
          phone: phone,
          email: null,
          address: null,
          contactPerson: null,
          notes: null,
          status: SupplierStatus.active,
          totalPurchaseCost: total,
          outstandingBalance: balance,
          purchaseCount: count,
          createdAt: now,
        ),
      );
    }
  }

  @override
  Future<PaginatedResult<Supplier>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Supplier>.from(_items);
    final status = query.filters['status'] as SupplierStatus?;
    if (status != null) pool = pool.where((s) => s.status == status).toList();
    return paginateInMemory<Supplier>(
      pool,
      query,
      matches: (item, q) => item.name.toLowerCase().contains(q) || item.phone.contains(q),
      sortKey: (item) => item.name,
    );
  }

  @override
  Future<Supplier> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((s) => s.id == id, orElse: () => throw StateError('Supplier not found'));
  }

  @override
  Future<List<Supplier>> allForPicker() async {
    await simulatedLatency();
    return _items.where((s) => s.status == SupplierStatus.active).toList();
  }

  @override
  Future<Supplier> create(SupplierDraft draft) async {
    await simulatedLatency();
    final created = Supplier(
      id: 'sup-${_nextId++}',
      name: draft.name,
      company: draft.company,
      phone: draft.phone,
      email: draft.email,
      address: draft.address,
      contactPerson: draft.contactPerson,
      notes: draft.notes,
      status: draft.status,
      totalPurchaseCost: 0,
      outstandingBalance: 0,
      purchaseCount: 0,
      createdAt: DateTime.now(),
    );
    _items.add(created);
    return created;
  }

  @override
  Future<Supplier> update(String id, SupplierDraft draft) async {
    await simulatedLatency();
    final index = _items.indexWhere((s) => s.id == id);
    if (index == -1) throw StateError('Supplier not found');
    final existing = _items[index];
    _items[index] = Supplier(
      id: existing.id,
      name: draft.name,
      company: draft.company,
      phone: draft.phone,
      email: draft.email,
      address: draft.address,
      contactPerson: draft.contactPerson,
      notes: draft.notes,
      status: draft.status,
      totalPurchaseCost: existing.totalPurchaseCost,
      outstandingBalance: existing.outstandingBalance,
      purchaseCount: existing.purchaseCount,
      createdAt: existing.createdAt,
    );
    return _items[index];
  }

  @override
  Future<void> setStatus(String id, SupplierStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((s) => s.id == id);
    if (index == -1) throw StateError('Supplier not found');
    final existing = _items[index];
    _items[index] = Supplier(
      id: existing.id,
      name: existing.name,
      company: existing.company,
      phone: existing.phone,
      email: existing.email,
      address: existing.address,
      contactPerson: existing.contactPerson,
      notes: existing.notes,
      status: status,
      totalPurchaseCost: existing.totalPurchaseCost,
      outstandingBalance: existing.outstandingBalance,
      purchaseCount: existing.purchaseCount,
      createdAt: existing.createdAt,
    );
  }
}
