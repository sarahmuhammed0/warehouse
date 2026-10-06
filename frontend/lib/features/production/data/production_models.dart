/// Production (spec §21/§22) — optional, business-type dependent.
enum ProductionStatus { planned, inProgress, completed, cancelled }

class BomLine {
  const BomLine({required this.materialProductId, required this.materialProductName, required this.quantityRequired, required this.unit});
  final String materialProductId;
  final String materialProductName;
  final int quantityRequired;
  final String unit;
}

class ProductionOrder {
  const ProductionOrder({
    required this.id,
    required this.productionNumber,
    required this.productId,
    required this.productName,
    required this.quantityPlanned,
    required this.quantityProduced,
    this.batchNumber,
    required this.materials,
    required this.cost,
    required this.status,
    this.assignedTo,
    this.startedAt,
    this.completedAt,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String productionNumber;
  final String productId;
  final String productName;
  final int quantityPlanned;
  final int quantityProduced;
  final String? batchNumber;
  final List<BomLine> materials;
  final double cost;
  final ProductionStatus status;
  final String? assignedTo;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;
  final DateTime createdAt;
}

class ProductionDraft {
  const ProductionDraft({
    required this.productId,
    required this.productName,
    required this.quantityPlanned,
    required this.materials,
    this.assignedUserId,
    this.assignedUserName,
    this.notes,
  });
  final String productId;
  final String productName;
  final int quantityPlanned;
  final List<BomLine> materials;

  /// Who the run is assigned to, as the id the server stores in
  /// `production_orders.assigned_user_id`.
  ///
  /// This was `assignedTo`, a free-typed name — which the server has nowhere to
  /// put, so [ApiProductionRepository.create] left it out of the request
  /// entirely and the form's Employee box discarded whatever was typed in it.
  final String? assignedUserId;

  /// The label the picker showed for [assignedUserId], carried so demo mode can
  /// display the assignment without a second lookup. The API path sends the id
  /// and reads the name back from the server.
  final String? assignedUserName;

  final String? notes;
}
