/// Customers (spec §18). `totalPurchases`/`outstandingBalance` are derived
/// values a real backend computes from Orders/Payments — kept here as plain
/// fields the local repository fakes, exactly the shape a future API
/// response would have.
class Customer {
  const Customer({
    required this.id,
    required this.code,
    required this.fullName,
    required this.phone,
    this.secondaryPhone,
    this.email,
    this.address,
    this.company,
    this.notes,
    required this.status,
    required this.totalPurchases,
    required this.outstandingBalance,
    required this.orderCount,
    required this.createdAt,
  });

  final String id;
  final String code;
  final String fullName;
  final String phone;
  final String? secondaryPhone;
  final String? email;
  final String? address;
  final String? company;
  final String? notes;
  final CustomerStatus status;
  final double totalPurchases;
  final double outstandingBalance;
  final int orderCount;
  final DateTime createdAt;
}

enum CustomerStatus { active, inactive }

class CustomerDraft {
  const CustomerDraft({
    required this.fullName,
    required this.phone,
    this.secondaryPhone,
    this.email,
    this.address,
    this.company,
    this.notes,
    this.status = CustomerStatus.active,
  });

  final String fullName;
  final String phone;
  final String? secondaryPhone;
  final String? email;
  final String? address;
  final String? company;
  final String? notes;
  final CustomerStatus status;
}
