/// Suppliers (spec §19).
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.company,
    required this.phone,
    this.email,
    this.address,
    this.contactPerson,
    this.notes,
    required this.status,
    required this.totalPurchaseCost,
    required this.outstandingBalance,
    required this.purchaseCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? company;
  final String phone;
  final String? email;
  final String? address;
  final String? contactPerson;
  final String? notes;
  final SupplierStatus status;
  final double totalPurchaseCost;
  final double outstandingBalance;
  final int purchaseCount;
  final DateTime createdAt;
}

enum SupplierStatus { active, inactive }

class SupplierDraft {
  const SupplierDraft({
    required this.name,
    this.company,
    required this.phone,
    this.email,
    this.address,
    this.contactPerson,
    this.notes,
    this.status = SupplierStatus.active,
  });

  final String name;
  final String? company;
  final String phone;
  final String? email;
  final String? address;
  final String? contactPerson;
  final String? notes;
  final SupplierStatus status;
}
