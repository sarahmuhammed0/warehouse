import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'purchase_models.dart';

abstract class PurchaseRepository {
  Future<PaginatedResult<Purchase>> list(PagedQuery query);
  Future<Purchase> getById(String id);
  Future<Purchase> create(PurchaseDraft draft);
  Future<Purchase> updateStatus(String id, PurchaseStatus status);
}

class LocalPurchaseRepository with DemoRepository implements PurchaseRepository {
  LocalPurchaseRepository() {
    _seed();
  }

  final List<Purchase> _items = [];
  int _nextNumber = 1;
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    _items.add(
      Purchase(
        id: 'pur-${_nextId++}',
        purchaseNumber: 'PUR-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        supplierId: 'sup-1',
        supplierName: 'Erbil Timber Supply',
        items: const [
          PurchaseLineItem(productId: 'prod-8', productName: 'Solid Pine Timber (2m)', quantity: 200, unitCost: 8, tax: 80),
        ],
        paidAmount: 1200,
        paymentMethod: 'Bank transfer',
        status: PurchaseStatus.completed,
        createdBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    );
  }

  @override
  Future<PaginatedResult<Purchase>> list(PagedQuery query) async {
    await simulatedLatency();
    final pool = List<Purchase>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return paginateInMemory<Purchase>(pool, query, matches: (item, q) => item.purchaseNumber.toLowerCase().contains(q) || item.supplierName.toLowerCase().contains(q));
  }

  @override
  Future<Purchase> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((p) => p.id == id, orElse: () => throw StateError('Purchase not found'));
  }

  @override
  Future<Purchase> create(PurchaseDraft draft) async {
    await simulatedLatency();
    final created = Purchase(
      id: 'pur-${_nextId++}',
      purchaseNumber: 'PUR-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
      supplierId: draft.supplierId,
      supplierName: draft.supplierName,
      items: [for (final i in draft.items) PurchaseLineItem(productId: i.productId, productName: i.productName, quantity: i.quantity, unitCost: i.unitCost, discount: i.discount, tax: i.tax)],
      paidAmount: draft.paidAmount,
      paymentMethod: draft.paymentMethod,
      status: PurchaseStatus.pending,
      notes: draft.notes,
      createdBy: 'Demo Admin',
      createdAt: DateTime.now(),
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<Purchase> updateStatus(String id, PurchaseStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((p) => p.id == id);
    if (index == -1) throw StateError('Purchase not found');
    final existing = _items[index];
    final updated = Purchase(
      id: existing.id,
      purchaseNumber: existing.purchaseNumber,
      supplierId: existing.supplierId,
      supplierName: existing.supplierName,
      items: existing.items,
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
