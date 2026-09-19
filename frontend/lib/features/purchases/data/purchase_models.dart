/// Purchases (spec §20).
enum PurchaseStatus { pending, completed, cancelled }

class PurchaseLineItem {
  const PurchaseLineItem({required this.productId, required this.productName, required this.quantity, required this.unitCost, this.discount = 0, this.tax = 0});
  final String productId;
  final String productName;
  final int quantity;
  final double unitCost;
  final double discount;
  final double tax;

  double get lineTotal => (quantity * unitCost) - discount + tax;
}

class Purchase {
  const Purchase({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    required this.items,
    required this.paidAmount,
    required this.paymentMethod,
    required this.status,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String purchaseNumber;
  final String supplierId;
  final String supplierName;
  final List<PurchaseLineItem> items;
  final double paidAmount;
  final String paymentMethod;
  final PurchaseStatus status;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  double get subtotal => items.fold(0, (sum, i) => sum + (i.quantity * i.unitCost));
  double get discountTotal => items.fold(0, (sum, i) => sum + i.discount);
  double get taxTotal => items.fold(0, (sum, i) => sum + i.tax);
  double get total => subtotal - discountTotal + taxTotal;
  double get remainingAmount => total - paidAmount;
}

class PurchaseItemDraft {
  const PurchaseItemDraft({required this.productId, required this.productName, required this.quantity, required this.unitCost, this.discount = 0, this.tax = 0});
  final String productId;
  final String productName;
  final int quantity;
  final double unitCost;
  final double discount;
  final double tax;
}

class PurchaseDraft {
  const PurchaseDraft({required this.supplierId, required this.supplierName, required this.items, this.paidAmount = 0, this.paymentMethod = 'Cash', this.notes});
  final String supplierId;
  final String supplierName;
  final List<PurchaseItemDraft> items;
  final double paidAmount;
  final String paymentMethod;
  final String? notes;
}
