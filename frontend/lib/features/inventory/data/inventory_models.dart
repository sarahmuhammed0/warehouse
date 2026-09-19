/// Inventory (spec §10/§11/§12). Stock levels themselves live on `Product`
/// (features/products) — this module owns *movements* (the append-only
/// history every stock change writes, §12) and *locations/transfers* (§11).
enum MovementType {
  purchase,
  sale,
  returnMovement,
  damage,
  adjustment,
  transfer,
  production,
  manualIncrease,
  manualDecrease,
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.previousQuantity,
    required this.newQuantity,
    required this.userName,
    required this.dateTime,
    this.location,
    this.note,
    this.referenceNumber,
  });

  final String id;
  final String productId;
  final String productName;
  final MovementType type;
  final int quantity;
  final int previousQuantity;
  final int newQuantity;
  final String userName;
  final DateTime dateTime;
  final String? location;
  final String? note;
  final String? referenceNumber;
}

class Warehouse {
  const Warehouse({
    required this.id,
    required this.name,
    required this.type,
    this.address,
    required this.isPrimary,
    required this.locationCount,
  });

  final String id;
  final String name;
  final String type;
  final String? address;
  final bool isPrimary;
  final int locationCount;
}

enum TransferStatus { pending, inTransit, completed, cancelled }

class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.transferNumber,
    required this.fromWarehouse,
    required this.toWarehouse,
    required this.productName,
    required this.quantity,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String transferNumber;
  final String fromWarehouse;
  final String toWarehouse;
  final String productName;
  final int quantity;
  final TransferStatus status;
  final String requestedBy;
  final DateTime createdAt;
  final String? notes;
}
