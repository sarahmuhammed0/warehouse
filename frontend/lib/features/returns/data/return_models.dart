/// Returns (spec §16).
enum ReturnStatus { requested, approved, rejected, completed }

enum ItemCondition { sellable, damaged }

class ReturnLineItem {
  const ReturnLineItem({required this.productId, required this.productName, required this.quantity, required this.condition});
  final String productId;
  final String productName;
  final int quantity;
  final ItemCondition condition;
}

class ProductReturn {
  const ProductReturn({
    required this.id,
    required this.returnNumber,
    required this.orderId,
    required this.orderNumber,
    this.customerName,
    required this.items,
    required this.reason,
    required this.refundAmount,
    required this.status,
    this.notes,
    required this.requestedBy,
    required this.createdAt,
  });

  final String id;
  final String returnNumber;
  final String orderId;
  final String orderNumber;
  final String? customerName;
  final List<ReturnLineItem> items;
  final String reason;
  final double refundAmount;
  final ReturnStatus status;
  final String? notes;
  final String requestedBy;
  final DateTime createdAt;

  /// Spec §16: inventory updates "per the configured return process" — this
  /// app's resolved policy (see `docs/architecture.md`'s ambiguity #2) is
  /// two-stage: Sellable-condition items restock only once Completed, never
  /// on mere Approval.
  bool get restocksOnCompletion => items.any((i) => i.condition == ItemCondition.sellable);
}

class ReturnItemDraft {
  const ReturnItemDraft({required this.productId, required this.productName, required this.quantity, required this.condition});
  final String productId;
  final String productName;
  final int quantity;
  final ItemCondition condition;
}

class ReturnDraft {
  const ReturnDraft({required this.orderId, required this.orderNumber, this.customerName, required this.items, required this.reason, required this.refundAmount, this.notes});
  final String orderId;
  final String orderNumber;
  final String? customerName;
  final List<ReturnItemDraft> items;
  final String reason;
  final double refundAmount;
  final String? notes;
}
