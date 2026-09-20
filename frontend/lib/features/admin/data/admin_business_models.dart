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
  final DateTime createdAt;

  // NOTE: no productCount/orderCount/salesTotal/userCount here on purpose.
  // Those are derived from the real demo records in `admin_metrics.dart` —
  // storing them again on the business row would give the System Admin's
  // cards a number that silently disagrees with the rows behind them.
}

class SystemActivityEntry {
  const SystemActivityEntry({required this.description, required this.businessName, required this.timestamp});
  final String description;
  final String businessName;
  final DateTime timestamp;
}
