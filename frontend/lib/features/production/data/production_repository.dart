import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'production_models.dart';

abstract class ProductionRepository {
  Future<PaginatedResult<ProductionOrder>> list(PagedQuery query);
  Future<ProductionOrder> getById(String id);
  Future<ProductionOrder> create(ProductionDraft draft);
  Future<ProductionOrder> updateStatus(String id, ProductionStatus status);

  /// A per-finished-product Bill of Materials template (§21) — editing this
  /// later never rewrites past production runs' own `materials` snapshot.
  Future<List<BomLine>> bomFor(String productId);
}

class LocalProductionRepository with DemoRepository implements ProductionRepository {
  LocalProductionRepository() {
    _seed();
  }

  final List<ProductionOrder> _items = [];
  int _nextNumber = 1;
  int _nextId = 1;

  final Map<String, List<BomLine>> _bomTemplates = {
    'prod-1': const [
      BomLine(materialProductId: 'prod-8', materialProductName: 'Solid Pine Timber (2m)', quantityRequired: 4, unit: 'Piece'),
      BomLine(materialProductId: 'prod-9', materialProductName: 'Upholstery Fabric (roll)', quantityRequired: 3, unit: 'Meter'),
      BomLine(materialProductId: 'prod-10', materialProductName: 'Wood Screws 4x40mm (box)', quantityRequired: 1, unit: 'Box'),
    ],
    'prod-12': const [
      BomLine(materialProductId: 'prod-8', materialProductName: 'Solid Pine Timber (2m)', quantityRequired: 6, unit: 'Piece'),
      BomLine(materialProductId: 'prod-11', materialProductName: 'Metal Table Legs (set of 4)', quantityRequired: 1, unit: 'Set'),
    ],
  };

  void _seed() {
    _items.add(
      ProductionOrder(
        id: 'prodn-${_nextId++}',
        productionNumber: 'PRDN-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
        productId: 'prod-1',
        productName: '3-Seat Sofa — Charcoal',
        quantityPlanned: 5,
        quantityProduced: 5,
        batchNumber: 'B-2026-001',
        materials: _bomTemplates['prod-1']!,
        cost: 640,
        status: ProductionStatus.completed,
        assignedTo: 'Production Team A',
        startedAt: DateTime.now().subtract(const Duration(days: 4)),
        completedAt: DateTime.now().subtract(const Duration(days: 2)),
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    );
  }

  @override
  Future<PaginatedResult<ProductionOrder>> list(PagedQuery query) async {
    await simulatedLatency();
    final pool = List<ProductionOrder>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return paginateInMemory<ProductionOrder>(pool, query, matches: (item, q) => item.productionNumber.toLowerCase().contains(q) || item.productName.toLowerCase().contains(q));
  }

  @override
  Future<ProductionOrder> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((p) => p.id == id, orElse: () => throw StateError('Production order not found'));
  }

  @override
  Future<List<BomLine>> bomFor(String productId) async {
    await simulatedLatency();
    return _bomTemplates[productId] ?? const [];
  }

  @override
  Future<ProductionOrder> create(ProductionDraft draft) async {
    await simulatedLatency();
    final created = ProductionOrder(
      id: 'prodn-${_nextId++}',
      productionNumber: 'PRDN-2026-${(_nextNumber++).toString().padLeft(6, '0')}',
      productId: draft.productId,
      productName: draft.productName,
      quantityPlanned: draft.quantityPlanned,
      quantityProduced: 0,
      materials: draft.materials,
      cost: 0,
      status: ProductionStatus.planned,
      assignedTo: draft.assignedTo,
      notes: draft.notes,
      createdAt: DateTime.now(),
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<ProductionOrder> updateStatus(String id, ProductionStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((p) => p.id == id);
    if (index == -1) throw StateError('Production order not found');
    final existing = _items[index];
    final updated = ProductionOrder(
      id: existing.id,
      productionNumber: existing.productionNumber,
      productId: existing.productId,
      productName: existing.productName,
      quantityPlanned: existing.quantityPlanned,
      quantityProduced: status == ProductionStatus.completed ? existing.quantityPlanned : existing.quantityProduced,
      batchNumber: existing.batchNumber,
      materials: existing.materials,
      cost: existing.cost,
      status: status,
      assignedTo: existing.assignedTo,
      startedAt: status == ProductionStatus.inProgress ? DateTime.now() : existing.startedAt,
      completedAt: status == ProductionStatus.completed ? DateTime.now() : existing.completedAt,
      notes: existing.notes,
      createdAt: existing.createdAt,
    );
    _items[index] = updated;
    return updated;
  }
}
