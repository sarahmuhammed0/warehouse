import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'admin_business_models.dart';

abstract class AdminRepository {
  Future<PaginatedResult<AdminBusiness>> listBusinesses(PagedQuery query);
  Future<AdminBusiness> getBusinessById(String id);
  Future<void> setBusinessStatus(String id, BusinessAccountStatus status);
  Future<List<SystemActivityEntry>> recentActivity();
}

class LocalAdminRepository with DemoRepository implements AdminRepository {
  LocalAdminRepository() {
    _seed();
  }

  final List<AdminBusiness> _items = [];
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    final seed = [
      ('Karwan Furniture Factory', 'Furniture Factory', '+9647701112233', 412, 1830, 284000.0, 6, 400),
      ('Erbil Central Warehouse', 'Warehouse', '+9647709998877', 1240, 3900, 0.0, 11, 240),
      ('City Storage Store', 'Storage Store', '+9647701234500', 88, 520, 41000.0, 3, 60),
      ('Northern Distribution Center', 'Distribution Center', '+9647705556677', 640, 2100, 0.0, 8, 30),
    ];
    for (final (name, type, phone, products, orders, sales, users, daysAgo) in seed) {
      _items.add(
        AdminBusiness(
          id: 'biz-${_nextId++}',
          name: name,
          businessType: type,
          phone: phone,
          // 3 active + 1 disabled — real status variety, so the dashboard's
          // Active/Disabled stat cards (and the filter they apply) have
          // something real to show rather than an always-empty filter.
          status: name == 'Northern Distribution Center' ? BusinessAccountStatus.disabled : BusinessAccountStatus.active,
          productCount: products,
          orderCount: orders,
          salesTotal: sales,
          userCount: users,
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
    final index = _items.indexWhere((b) => b.id == id);
    if (index == -1) throw StateError('Business not found');
    final existing = _items[index];
    _items[index] = AdminBusiness(
      id: existing.id,
      name: existing.name,
      businessType: existing.businessType,
      logoUrl: existing.logoUrl,
      phone: existing.phone,
      email: existing.email,
      address: existing.address,
      status: status,
      productCount: existing.productCount,
      orderCount: existing.orderCount,
      salesTotal: existing.salesTotal,
      userCount: existing.userCount,
      createdAt: existing.createdAt,
    );
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
