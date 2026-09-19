/// System Admin's view of a business (spec §2/§36/§37) — deliberately a
/// separate, smaller model from anything a business itself would see about
/// its own record; this is the platform-level cross-tenant view only
/// `system_admin` accounts are ever authorized to read (see
/// `docs/multi-tenancy.md`'s "System Admin boundary" for the backend rule
/// this frontend model assumes will exist).
enum BusinessAccountStatus { active, disabled }

class AdminBusiness {
  const AdminBusiness({
    required this.id,
    required this.name,
    required this.businessType,
    this.logoUrl,
    required this.phone,
    this.email,
    this.address,
    required this.status,
    required this.productCount,
    required this.orderCount,
    required this.salesTotal,
    required this.userCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String businessType;
  final String? logoUrl;
  final String phone;
  final String? email;
  final String? address;
  final BusinessAccountStatus status;
  final int productCount;
  final int orderCount;
  final double salesTotal;
  final int userCount;
  final DateTime createdAt;
}

class SystemActivityEntry {
  const SystemActivityEntry({required this.description, required this.businessName, required this.timestamp});
  final String description;
  final String businessName;
  final DateTime timestamp;
}
