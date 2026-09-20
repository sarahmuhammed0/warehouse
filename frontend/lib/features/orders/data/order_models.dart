/// Orders + Sales share one entity (architecture's resolved ambiguity:
/// "one unified `orders` table, `order_type` flag" — §13/§14). `quickSale`
/// is the Sales module's fast checkout path (defaults straight to
/// Completed); `standard` is the full Orders workflow with the nine-value
/// status list.
enum OrderType { quickSale, standard }

enum OrderStatus { draft, pending, confirmed, processing, ready, completed, cancelled, returned, partiallyReturned }

enum PaymentStatus { paid, partiallyPaid, unpaid }

enum PaymentMethod { cash, bankTransfer, card, other }

class OrderLineItem {
  const OrderLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    this.tax = 0,
  });

  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double tax;

  double get lineTotal => (quantity * unitPrice) - discount + tax;
}

class Order {
  const Order({
    required this.id,
    required this.businessId,
    required this.orderNumber,
    required this.orderType,
    this.customerId,
    this.customerName,
    required this.items,
    required this.extraCharges,
    required this.paidAmount,
    required this.paymentMethod,
    required this.status,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;

  /// Owning tenant — see `Product.businessId`.
  final String businessId;
  final String orderNumber;
  final OrderType orderType;
  final String? customerId;
  final String? customerName;
  final List<OrderLineItem> items;
  final double extraCharges;
  final double paidAmount;
  final PaymentMethod paymentMethod;
  final OrderStatus status;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  double get subtotal => items.fold(0, (sum, i) => sum + (i.quantity * i.unitPrice));
  double get discountTotal => items.fold(0, (sum, i) => sum + i.discount);
  double get taxTotal => items.fold(0, (sum, i) => sum + i.tax);
  double get grandTotal => subtotal - discountTotal + taxTotal + extraCharges;
  double get remainingAmount => grandTotal - paidAmount;

  PaymentStatus get paymentStatus {
    if (paidAmount <= 0) return PaymentStatus.unpaid;
    if (remainingAmount <= 0) return PaymentStatus.paid;
    return PaymentStatus.partiallyPaid;
  }

  /// Statuses a Draft/Pending/Confirmed/Processing/Ready order can legally
  /// move to next — a fixed state machine (spec §14), never an arbitrary
  /// jump the UI allows.
  List<OrderStatus> get allowedNextStatuses => switch (status) {
        OrderStatus.draft => [OrderStatus.pending, OrderStatus.cancelled],
        OrderStatus.pending => [OrderStatus.confirmed, OrderStatus.cancelled],
        OrderStatus.confirmed => [OrderStatus.processing, OrderStatus.cancelled],
        OrderStatus.processing => [OrderStatus.ready, OrderStatus.cancelled],
        OrderStatus.ready => [OrderStatus.completed, OrderStatus.cancelled],
        OrderStatus.completed => [OrderStatus.returned, OrderStatus.partiallyReturned],
        OrderStatus.cancelled => [OrderStatus.pending], // "reopen where permitted" (§14) — narrow: un-cancel only
        OrderStatus.returned => [],
        OrderStatus.partiallyReturned => [],
      };
}

class OrderItemDraft {
  const OrderItemDraft({required this.productId, required this.productName, required this.quantity, required this.unitPrice, this.discount = 0, this.tax = 0});
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double tax;
}

class OrderDraft {
  const OrderDraft({
    required this.orderType,
    this.customerId,
    this.customerName,
    required this.items,
    this.extraCharges = 0,
    this.paidAmount = 0,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
  });

  final OrderType orderType;
  final String? customerId;
  final String? customerName;
  final List<OrderItemDraft> items;
  final double extraCharges;
  final double paidAmount;
  final PaymentMethod paymentMethod;
  final String? notes;
}
