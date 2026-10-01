import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'inventory_models.dart';
import 'inventory_repository.dart';

/// Inventory against the real backend (§10/§11/§12).
///
/// Satisfies the same [InventoryRepository] interface as the demo version, so
/// no screen changes when this replaces it.
class ApiInventoryRepository implements InventoryRepository {
  ApiInventoryRepository(this._client);

  final ApiClient _client;

  /// The API's `movement_type` values, which are §12's own vocabulary. Kept as
  /// one map in both directions so a type cannot be spelled one way when
  /// writing and another when reading.
  static const _wireNames = {
    MovementType.purchase: 'purchase',
    MovementType.sale: 'sale',
    MovementType.returnMovement: 'return',
    MovementType.damage: 'damage',
    MovementType.adjustment: 'adjustment',
    MovementType.transfer: 'transfer',
    MovementType.production: 'production',
    MovementType.manualIncrease: 'manual_increase',
    MovementType.manualDecrease: 'manual_decrease',
  };

  static MovementType _typeFrom(String? wire) {
    for (final entry in _wireNames.entries) {
      if (entry.value == wire) return entry.key;
    }
    // A type this build does not know about is still a real movement, and
    // hiding the row would be worse than showing it as an adjustment.
    return MovementType.adjustment;
  }

  static StockMovement _movementFrom(Map<String, dynamic> json) => StockMovement(
    id: '${json['id']}',
    productId: '${json['productId']}',
    productName: (json['productName'] as String?) ?? '',
    type: _typeFrom(json['movementType'] as String?),
    // Quantities are DECIMAL(14,3) server-side and this model is an int. A
    // fractional quantity is rounded for display rather than truncated; the
    // server keeps the exact figure either way.
    quantity: (json['quantity'] as num?)?.round() ?? 0,
    previousQuantity: (json['quantityBefore'] as num?)?.round() ?? 0,
    newQuantity: (json['quantityAfter'] as num?)?.round() ?? 0,
    userName: (json['userName'] as String?) ?? '',
    dateTime: DateTime.tryParse('${json['movedAt']}') ?? DateTime.now(),
    location: (json['locationName'] as String?) ?? json['warehouseName'] as String?,
    note: json['note'] as String?,
    referenceNumber: json['referenceNumber'] as String?,
  );

  @override
  Future<PaginatedResult<StockMovement>> listMovements(PagedQuery query) async {
    final result = await _client.getList('/inventory/movements?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _movementFrom(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<List<Warehouse>> listWarehouses() async {
    // The full list, not `/warehouses/options`: the screen shows each
    // warehouse's type, address and how many locations are inside it, and the
    // options endpoint deliberately returns only id/name/isDefault.
    final result = await _client.getList('/warehouses?pageSize=100');
    return result.data.map((row) {
      final json = row as Map<String, dynamic>;
      return Warehouse(
        id: '${json['id']}',
        name: (json['name'] as String?) ?? '',
        type: _locationTypeLabel(json['locationType'] as String?),
        address: json['address'] as String?,
        isPrimary: json['isDefault'] == true,
        locationCount: (json['locationCount'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// §11's `location_type` enum, as a label. The demo data used the same
  /// words, so the screens already read this way.
  static String _locationTypeLabel(String? type) => switch (type) {
    'warehouse' => 'Warehouse',
    'showroom' => 'Showroom',
    'production_area' => 'Production area',
    'storage_room' => 'Storage room',
    'outdoor' => 'Outdoor',
    'other' => 'Other',
    _ => 'Warehouse',
  };

  /// The business's default warehouse, which is where a movement with no
  /// location named belongs — the same resolution `ApiProductRepository`
  /// uses, and what §11's "default" is for.
  Future<String> _defaultWarehouseId() async {
    final result = await _client.getList('/warehouses/options');
    if (result.data.isEmpty) {
      throw StateError('No warehouse exists yet. Create one before moving stock.');
    }
    final rows = result.data.cast<Map<String, dynamic>>();
    final preferred = rows.firstWhere(
      (row) => row['isDefault'] == true,
      orElse: () => rows.first,
    );
    return '${preferred['id']}';
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
    // `currentQuantity` is deliberately unused here. The demo version needed
    // it to compute before/after itself; the server reads the live level under
    // a row lock, which is the only figure that cannot be stale (§12).
    final warehouseId = await _defaultWarehouseId();

    await _client.postJson('/inventory/adjust', {
      'productId': int.tryParse(productId),
      'warehouseId': int.tryParse(warehouseId),
      // Signed: the endpoint takes the delta, not an absolute level.
      'quantity': delta,
      'movementType': _wireNames[type] ?? 'adjustment',
      'note': note,
    });

    // The adjust endpoint answers with the new level rather than the movement
    // row, so the row is read back — it is what the caller returns to the
    // Movements list, and reading it keeps the server as the one source of
    // what was recorded.
    final latest = await listMovements(
      PagedQuery(pageSize: 1, filters: {'productId': int.tryParse(productId)}),
    );
    if (latest.items.isNotEmpty) return latest.items.first;

    // Only reachable if the ledger read fails after a successful write. The
    // adjustment did happen, so this describes it rather than throwing.
    return StockMovement(
      id: '',
      productId: productId,
      productName: productName,
      type: type,
      quantity: delta.abs(),
      previousQuantity: currentQuantity,
      newQuantity: currentQuantity + delta,
      userName: '',
      dateTime: DateTime.now(),
      note: note,
    );
  }

  static const _transferStatuses = <String, TransferStatus>{
    'pending': TransferStatus.pending,
    'in_transit': TransferStatus.inTransit,
    'completed': TransferStatus.completed,
    'cancelled': TransferStatus.cancelled,
  };

  @override
  Future<PaginatedResult<StockTransfer>> listTransfers(PagedQuery query) async {
    // §11's transfers are documents with their own lifecycle, so this reads
    // them rather than reconstructing them from the ledger: a ledger row knows
    // a quantity moved, but not the transfer number it belonged to nor whether
    // that transfer is still pending — which is precisely what this list is
    // for. Reading movements could only ever show completed ones.
    final result = await _client.getList('/stock-transfers?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;

    return PaginatedResult(
      items: result.data.cast<Map<String, dynamic>>().map((row) {
        final itemCount = (row['itemCount'] as num?)?.toInt() ?? 0;
        final first = (row['firstProductName'] as String?) ?? '';
        return StockTransfer(
          id: '${row['id']}',
          transferNumber: (row['transferNumber'] as String?) ?? '',
          fromWarehouse: (row['fromWarehouseName'] as String?) ?? '',
          toWarehouse: (row['toWarehouseName'] as String?) ?? '',
          // A transfer can carry several products and this row has space for
          // one name. The extras are counted rather than dropped — "and 2
          // more" is true, where showing only the first would not be.
          productName: itemCount > 1 ? '$first  + ${itemCount - 1} more' : first,
          quantity: ((row['totalQuantity'] as num?)?.toDouble() ?? 0).round(),
          status: _transferStatuses[row['status']] ?? TransferStatus.pending,
          requestedBy: (row['createdByName'] as String?) ?? '',
          createdAt: DateTime.tryParse('${row['createdAt']}') ?? DateTime.now(),
          notes: row['note'] as String?,
        );
      }).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<StockTransfer> createTransfer({
    required String fromWarehouseId,
    required String toWarehouseId,
    required String productName,
    required int quantity,
    String? productId,
    String? notes,
  }) async {
    if (productId == null) {
      // Resolving the product by NAME would be a real bug rather than a
      // limitation: §8 does not make product names unique, so a name lookup
      // could move a different product's stock.
      throw StateError('A transfer needs the product it moves, not just its name.');
    }

    // Creates the §11 DOCUMENT, not the bare two-legged movement that
    // `/inventory/transfer` performs. The two do the same thing to stock, but
    // only this one leaves a transfer with a number and a status — and the
    // list above reads transfers, so a movement filed the other way would move
    // the goods and then never appear.
    //
    // Born `completed`, which is the dialog's meaning: a clerk moving a pallet
    // now and writing it down as they do it. A transfer that needed approval
    // first would need somewhere to approve it, which is a screen this module
    // does not have.
    final created = await _client.postJson('/stock-transfers', {
      'fromWarehouseId': int.tryParse(fromWarehouseId),
      'toWarehouseId': int.tryParse(toWarehouseId),
      'items': [
        {'productId': int.tryParse(productId), 'quantity': quantity},
      ],
      'note': notes,
      'status': 'completed',
    });

    return StockTransfer(
      id: '${created['id']}',
      transferNumber: (created['transferNumber'] as String?) ?? '',
      fromWarehouse: (created['fromWarehouseName'] as String?) ?? fromWarehouseId,
      toWarehouse: (created['toWarehouseName'] as String?) ?? toWarehouseId,
      productName: productName,
      quantity: quantity,
      status: _transferStatuses[created['status']] ?? TransferStatus.completed,
      requestedBy: (created['createdByName'] as String?) ?? '',
      createdAt: DateTime.tryParse('${created['createdAt']}') ?? DateTime.now(),
      notes: notes,
    );
  }
}
