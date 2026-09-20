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
    this.lastPasswordResetAt,
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

  /// When the System Admin last reset this business account's password.
  ///
  /// Demo-only, and deliberately so: `DemoAuthRepository` holds no
  /// per-account password at all (its `login` ignores the password argument
  /// and `changePassword` is a no-op), so there is nothing a frontend reset
  /// could truthfully change. Rather than leave the control dead or pop a
  /// success message for an action that did nothing, the reset records this
  /// timestamp — real local state, shown on the detail screen, replaced by
  /// a real `POST /api/admin/businesses/:id/reset-password` when backend
  /// work resumes (docs/frontend-backend-contract-notes.md).
  final DateTime? lastPasswordResetAt;

  // NOTE: no productCount/orderCount/salesTotal/userCount here on purpose.
  // Those are derived from the real demo records in `admin_metrics.dart` —
  // storing them again on the business row would give the System Admin's
  // cards a number that silently disagrees with the rows behind them.

  AdminBusiness copyWith({
    String? name,
    String? businessType,
    String? phone,
    String? email,
    String? address,
    BusinessAccountStatus? status,
    DateTime? lastPasswordResetAt,
  }) {
    return AdminBusiness(
      id: id,
      name: name ?? this.name,
      businessType: businessType ?? this.businessType,
      logoUrl: logoUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      status: status ?? this.status,
      createdAt: createdAt,
      lastPasswordResetAt: lastPasswordResetAt ?? this.lastPasswordResetAt,
    );
  }
}

/// The editable shape of a business, for the System Admin's Edit screen —
/// mirrors [AdminBusiness] minus what the admin cannot change (id, created
/// date, status, which has its own Disable/Activate control, and the
/// derived counts that live in `admin_metrics.dart`).
class AdminBusinessDraft {
  const AdminBusinessDraft({
    required this.name,
    required this.businessType,
    required this.phone,
    this.email,
    this.address,
  });

  final String name;
  final String businessType;
  final String phone;
  final String? email;
  final String? address;
}

class SystemActivityEntry {
  const SystemActivityEntry({required this.description, required this.businessName, required this.timestamp});
  final String description;
  final String businessName;
  final DateTime timestamp;
}
