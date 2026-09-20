import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_businesses.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'admin_business_models.dart';

abstract class AdminRepository {
  Future<PaginatedResult<AdminBusiness>> listBusinesses(PagedQuery query);
  Future<AdminBusiness> getBusinessById(String id);
  Future<void> setBusinessStatus(String id, BusinessAccountStatus status);
  Future<List<SystemActivityEntry>> recentActivity();

  /// Spec §57's "Edit" control — updates the business profile in place.
  Future<AdminBusiness> updateBusiness(String id, AdminBusinessDraft draft);

  /// Spec §57's "Reset password" control. Returns the updated record so the
  /// caller can show when the reset happened; see
  /// [AdminBusiness.lastPasswordResetAt] for why no password is stored.
  Future<AdminBusiness> resetBusinessPassword(String id);
}

class LocalAdminRepository with DemoRepository implements AdminRepository {
  LocalAdminRepository() {
    _seed();
  }

  final List<AdminBusiness> _items = [];

  /// Identity (id/name/type) comes from `kDemoBusinesses`, the same list the
  /// products/orders/employees repositories tag their records with — so a
  /// business the admin can open always has records behind it, and its
  /// counts come from `admin_metrics.dart` rather than from here.
  void _seed() {
    final now = DateTime.now();
    const contacts = {
      kDemoBusinessKarwan: ('+9647701112233', 400),
      kDemoBusinessErbil: ('+9647709998877', 240),
      kDemoBusinessCityStore: ('+9647701234500', 60),
      kDemoBusinessNorthern: ('+9647705556677', 30),
    };
    for (final business in kDemoBusinesses) {
      final (phone, daysAgo) = contacts[business.id]!;
      _items.add(
        AdminBusiness(
          id: business.id,
          name: business.name,
          businessType: business.type,
          phone: phone,
          // 3 active + 1 disabled — real status variety, so the dashboard's
          // Active/Disabled stat cards (and the filter they apply) have
          // something real to show rather than an always-empty filter.
          status: business.id == kDemoBusinessNorthern ? BusinessAccountStatus.disabled : BusinessAccountStatus.active,
          createdAt: now.subtract(Duration(days: daysAgo)),
        ),
      );
    }
  }

  @override
  Future<PaginatedResult<AdminBusiness>> listBusinesses(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<AdminBusiness>.from(_items);
    final status = query.filters['status'] as BusinessAccountStatus?;
    if (status != null) pool = pool.where((b) => b.status == status).toList();
    return paginateInMemory<AdminBusiness>(pool, query, matches: (item, q) => item.name.toLowerCase().contains(q), sortKey: (item) => item.name);
  }

  @override
  Future<AdminBusiness> getBusinessById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((b) => b.id == id, orElse: () => throw StateError('Business not found'));
  }

  @override
  Future<void> setBusinessStatus(String id, BusinessAccountStatus status) async {
    await simulatedLatency();
    _replace(id, (existing) => existing.copyWith(status: status));
  }

  @override
  Future<AdminBusiness> updateBusiness(String id, AdminBusinessDraft draft) async {
    await simulatedLatency();
    // Built explicitly rather than through `copyWith`: email and address are
    // optional, and the admin clearing one must actually clear it —
    // `copyWith`'s `?? this.email` would silently keep the old value and
    // make a field impossible to blank out once set.
    return _replace(
      id,
      (existing) => AdminBusiness(
        id: existing.id,
        name: draft.name,
        businessType: draft.businessType,
        logoUrl: existing.logoUrl,
        phone: draft.phone,
        email: draft.email,
        address: draft.address,
        status: existing.status,
        createdAt: existing.createdAt,
        lastPasswordResetAt: existing.lastPasswordResetAt,
      ),
    );
  }

  @override
  Future<AdminBusiness> resetBusinessPassword(String id) async {
    await simulatedLatency();
    return _replace(id, (existing) => existing.copyWith(lastPasswordResetAt: DateTime.now()));
  }

  AdminBusiness _replace(String id, AdminBusiness Function(AdminBusiness) update) {
    final index = _items.indexWhere((b) => b.id == id);
    if (index == -1) throw StateError('Business not found');
    final updated = update(_items[index]);
    _items[index] = updated;
    return updated;
  }

  @override
  Future<List<SystemActivityEntry>> recentActivity() async {
    await simulatedLatency();
    final now = DateTime.now();
    return [
      SystemActivityEntry(description: 'New business account created', businessName: _items.first.name, timestamp: now.subtract(const Duration(hours: 2))),
      SystemActivityEntry(description: 'Login', businessName: _items[1].name, timestamp: now.subtract(const Duration(hours: 5))),
      SystemActivityEntry(description: 'Settings changed', businessName: _items[2].name, timestamp: now.subtract(const Duration(days: 1))),
    ];
  }
}
