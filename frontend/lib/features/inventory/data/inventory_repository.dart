import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import '../../products/data/product_repository.dart';
import 'inventory_models.dart';

abstract class InventoryRepository {
  Future<PaginatedResult<StockMovement>> listMovements(PagedQuery query);
  Future<List<Warehouse>> listWarehouses();
  Future<PaginatedResult<StockTransfer>> listTransfers(PagedQuery query);
  Future<StockMovement> recordAdjustment({
    required String productId,
    required String productName,
    required int currentQuantity,
    required int delta,
    required MovementType type,
    String? note,
  });
  Future<StockTransfer> createTransfer({
    required String fromWarehouseId,
    required String toWarehouseId,
    required String productName,
    required int quantity,
    String? notes,
  });
}

class LocalInventoryRepository with DemoRepository implements InventoryRepository {
  LocalInventoryRepository(this._productRepository);

  final ProductRepository _productRepository;
  final List<StockMovement> _movements = [];
  final List<StockTransfer> _transfers = [];
  int _movementId = 1;
  int _transferId = 1;

  // Seeded lazily, on first real use, and always awaited by the caller —
  // never fired-and-forgotten from the constructor. An un-awaited async
  // constructor call leaves its `simulatedLatency()` timer untracked by
  // anything, which `flutter test` correctly flags as "a Timer is still
  // pending after the widget tree was disposed" the moment a test's
  // ProviderScope is torn down before that timer fires.
  bool _seeded = false;

  final List<Warehouse> _warehouses = const [
    Warehouse(id: 'wh-1', name: 'Main Warehouse', type: 'Warehouse', address: 'Industrial Zone, Bay 4', isPrimary: true, locationCount: 12),
    Warehouse(id: 'wh-2', name: 'Showroom', type: 'Showroom', address: 'City Center Branch', isPrimary: false, locationCount: 4),
    Warehouse(id: 'wh-3', name: 'Production Floor', type: 'Production area', address: null, isPrimary: false, locationCount: 3),
  ];

  Future<void> _ensureSeeded() async {
    if (_seeded) return;
    _seeded = true;
    final products = await _productRepository.allForPicker();
    final now = DateTime.now();
    final types = [MovementType.purchase, MovementType.sale, MovementType.adjustment, MovementType.transfer];
    for (var i = 0; i < products.length && i < 10; i++) {
      final product = products[i];
      _movements.add(
        StockMovement(
          id: 'mov-${_movementId++}',
          productId: product.id,
          productName: product.name,
          type: types[i % types.length],
          quantity: 5 + i,
          previousQuantity: product.currentQuantity,
          newQuantity: product.currentQuantity + (i.isEven ? 5 + i : -(5 + i)),
          userName: 'Demo Admin',
          dateTime: now.subtract(Duration(hours: i * 6)),
          location: product.warehouseName,
          referenceNumber: 'REF-${1000 + i}',
        ),
      );
    }
    _transfers.add(
      StockTransfer(
        id: 'tr-${_transferId++}',
        transferNumber: 'TRF-2026-000001',
        fromWarehouse: 'Main Warehouse',
        toWarehouse: 'Showroom',
        productName: products.isNotEmpty ? products.first.name : 'Sample product',
        quantity: 4,
        status: TransferStatus.completed,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
    );
    _transfers.add(
      StockTransfer(
        id: 'tr-${_transferId++}',
        transferNumber: 'TRF-2026-000002',
        fromWarehouse: 'Main Warehouse',
        toWarehouse: 'Production Floor',
        productName: products.length > 1 ? products[1].name : 'Sample product',
        quantity: 6,
        status: TransferStatus.pending,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
    );
    _transfers.add(
      StockTransfer(
        id: 'tr-${_transferId++}',
        transferNumber: 'TRF-2026-000003',
        fromWarehouse: 'Production Floor',
        toWarehouse: 'Showroom',
        productName: products.length > 2 ? products[2].name : 'Sample product',
        quantity: 3,
        status: TransferStatus.inTransit,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
    );
    _transfers.add(
      StockTransfer(
        id: 'tr-${_transferId++}',
        transferNumber: 'TRF-2026-000004',
        fromWarehouse: 'Showroom',
        toWarehouse: 'Main Warehouse',
        productName: products.length > 3 ? products[3].name : 'Sample product',
        quantity: 2,
        status: TransferStatus.cancelled,
        requestedBy: 'Demo Admin',
        createdAt: now.subtract(const Duration(days: 6)),
      ),
    );
  }

  @override
  Future<PaginatedResult<StockMovement>> listMovements(PagedQuery query) async {
    await _ensureSeeded();
    await simulatedLatency();
    var pool = List<StockMovement>.from(_movements)..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final productId = query.filters['productId'] as String?;
    if (productId != null) pool = pool.where((m) => m.productId == productId).toList();
    final type = query.filters['type'] as MovementType?;
    if (type != null) pool = pool.where((m) => m.type == type).toList();
    return paginateInMemory<StockMovement>(
      pool,
      query,
      matches: (item, q) => item.productName.toLowerCase().contains(q) || (item.referenceNumber?.toLowerCase().contains(q) ?? false),
    );
  }

  @override
  Future<List<Warehouse>> listWarehouses() async {
    await _ensureSeeded();
    await simulatedLatency();
    return _warehouses;
  }

  @override
  Future<PaginatedResult<StockTransfer>> listTransfers(PagedQuery query) async {
    await _ensureSeeded();
    await simulatedLatency();
    final pool = List<StockTransfer>.from(_transfers)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return paginateInMemory<StockTransfer>(
      pool,
      query,
      matches: (item, q) => item.transferNumber.toLowerCase().contains(q) || item.productName.toLowerCase().contains(q),
    );
  }

  @override
  Future<StockMovement> recordAdjustment({
    required String productId,
    required String productName,
    required int currentQuantity,
    required int delta,
    required MovementType type,
    String? note,
  }) async {
    await simulatedLatency();
    final movement = StockMovement(
      id: 'mov-${_movementId++}',
      productId: productId,
      productName: productName,
      type: type,
      quantity: delta.abs(),
      previousQuantity: currentQuantity,
      newQuantity: currentQuantity + delta,
      userName: 'Demo Admin',
      dateTime: DateTime.now(),
      note: note,
    );
    _movements.insert(0, movement);
    return movement;
  }

  @override
  Future<StockTransfer> createTransfer({
    required String fromWarehouseId,
    required String toWarehouseId,
    required String productName,
    required int quantity,
    String? notes,
  }) async {
    await simulatedLatency();
    final from = _warehouses.firstWhere((w) => w.id == fromWarehouseId);
    final to = _warehouses.firstWhere((w) => w.id == toWarehouseId);
    final transfer = StockTransfer(
      id: 'tr-${_transferId++}',
      transferNumber: 'TRF-2026-${(_transferId).toString().padLeft(6, '0')}',
      fromWarehouse: from.name,
      toWarehouse: to.name,
      productName: productName,
      quantity: quantity,
      status: TransferStatus.pending,
      requestedBy: 'Demo Admin',
      createdAt: DateTime.now(),
      notes: notes,
    );
    _transfers.insert(0, transfer);
    return transfer;
  }
}
