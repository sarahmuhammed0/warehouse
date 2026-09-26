import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/network/providers.dart';
import '../../../core/repositories/paged_query.dart';
// Same payload as a self-registration — see createBusiness's doc comment.
import '../../auth/data/registration_repository.dart';

/// The System Admin's registration queue (§2's "create/activate/disable
/// business accounts", reached by approving an application instead of
/// creating the business by hand).
///
/// A SEPARATE, NARROW INTERFACE rather than more methods on
/// `AdminRepository`, deliberately. `AdminRepository` covers the whole admin
/// dashboard — metrics, activity, per-business edit, password reset — and
/// the backend has endpoints for none of that yet. Widening it would force a
/// real implementation to stub methods it cannot honour, and a stub that
/// throws at runtime is worse than an interface that never promised. This
/// interface contains exactly what `/api/admin/businesses` actually
/// implements, so its real version is complete rather than partial.
class BusinessRegistration {
  const BusinessRegistration({
    required this.id,
    required this.name,
    required this.businessType,
    required this.phone,
    required this.status,
    required this.createdAt,
    this.currency,
    this.ownerName,
    this.ownerPhone,
    this.rejectionReason,
    this.approvedAt,
    this.rejectedAt,
  });

  final String id;
  final String name;

  /// The backend's wire value, e.g. `furniture_factory`.
  final String businessType;
  final String phone;

  /// `pending` | `active` | `disabled` | `rejected`.
  final String status;
  final DateTime createdAt;
  final String? currency;
  final String? ownerName;
  final String? ownerPhone;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  bool get isPending => status == 'pending';

  static DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value');

  factory BusinessRegistration.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>?;
    return BusinessRegistration(
      id: '${json['id']}',
      name: (json['name'] as String?) ?? '',
      businessType: (json['businessType'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      // The backend sends dates as strings (the pool uses dateStrings), so a
      // failure to parse must not take the whole queue down with it.
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      currency: json['currency'] as String?,
      ownerName: owner?['name'] as String?,
      ownerPhone: owner?['phone'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      approvedAt: _date(json['approvedAt']),
      rejectedAt: _date(json['rejectedAt']),
    );
  }
}

abstract class RegistrationQueueRepository {
  /// [status] filters server-side; null lists every business.
  Future<PaginatedResult<BusinessRegistration>> list(PagedQuery query, {String? status});

  Future<BusinessRegistration> approve(String id);

  /// [reason] is required by the backend and shown to the applicant when
  /// they next try to sign in.
  Future<BusinessRegistration> reject(String id, String reason);

  /// §2's "create factory/warehouse/storage-store accounts" — the
  /// administrator creating a business directly. It is created **active**:
  /// an administrator doing it by hand IS the approval, so there is no
  /// pending step to approve afterwards.
  ///
  /// Takes the same [RegistrationDraft] a self-registration submits, because
  /// the payload is identical — the only difference is who asked and what
  /// status results. Two copies of these nine fields would only drift.
  Future<void> createBusiness(RegistrationDraft draft);
}

class ApiRegistrationQueueRepository implements RegistrationQueueRepository {
  ApiRegistrationQueueRepository(this._client);

  final ApiClient _client;

  @override
  Future<PaginatedResult<BusinessRegistration>> list(PagedQuery query, {String? status}) async {
    final params = <String, String>{
      'page': '${query.page}',
      'pageSize': '${query.pageSize}',
      'status': ?status,
      if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
      'sort': ?query.sortField,
      if (query.sortField != null) 'direction': query.sortAscending ? 'asc' : 'desc',
    };
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

    // A list envelope: `data` is an array, paging is under `meta.pagination`.
    final result = await _client.getList('/admin/businesses?$qs');
    final items = result.data
        .map((row) => BusinessRegistration.fromJson(row as Map<String, dynamic>))
        .toList();
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: items,
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? items.length,
    );
  }

  @override
  Future<BusinessRegistration> approve(String id) async {
    final json = await _client.postJson('/admin/businesses/$id/approve', const {});
    return BusinessRegistration.fromJson(json);
  }

  @override
  Future<BusinessRegistration> reject(String id, String reason) async {
    final json = await _client.postJson('/admin/businesses/$id/reject', {'reason': reason});
    return BusinessRegistration.fromJson(json);
  }

  @override
  Future<void> createBusiness(RegistrationDraft draft) async {
    // Returns {businessId, ownerId} rather than a business view, so there is
    // nothing useful to hand back — the caller refetches instead.
    await _client.postJson('/admin/businesses', draft.toJson());
  }
}

/// Demo-mode stand-in so the queue screen is usable with the backend off.
/// Holds its applications in memory and applies the same rule the backend
/// enforces: a decision can only be made once.
class DemoRegistrationQueueRepository implements RegistrationQueueRepository {
  DemoRegistrationQueueRepository() {
    final now = DateTime.now();
    _items.addAll([
      BusinessRegistration(
        id: 'demo-reg-1',
        name: 'Zagros Timber Works',
        businessType: 'furniture_factory',
        phone: '+9647510004001',
        status: 'pending',
        createdAt: now.subtract(const Duration(hours: 5)),
        currency: 'IQD',
        ownerName: 'Dilan Hasan',
        ownerPhone: '+9647510004002',
      ),
      BusinessRegistration(
        id: 'demo-reg-2',
        name: 'Tigris Cold Storage',
        businessType: 'storage_store',
        phone: '+9647510004003',
        status: 'pending',
        createdAt: now.subtract(const Duration(days: 2)),
        currency: 'IQD',
        ownerName: 'Noor Salim',
        ownerPhone: '+9647510004004',
      ),
    ]);
  }

  final List<BusinessRegistration> _items = [];

  @override
  Future<PaginatedResult<BusinessRegistration>> list(PagedQuery query, {String? status}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final filtered = _items.where((b) => status == null || b.status == status).toList();
    return PaginatedResult(
      items: filtered,
      page: 1,
      pageSize: filtered.length,
      total: filtered.length,
    );
  }

  @override
  Future<BusinessRegistration> approve(String id) => _decide(id, approved: true, reason: null);

  @override
  Future<BusinessRegistration> reject(String id, String reason) => _decide(id, approved: false, reason: reason);

  @override
  Future<void> createBusiness(RegistrationDraft draft) async {
    // An administrator-created business is active immediately, so it never
    // enters the pending queue this repository serves.
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<BusinessRegistration> _decide(String id, {required bool approved, String? reason}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final index = _items.indexWhere((b) => b.id == id);
    if (index == -1) throw StateError('No such registration: $id');
    final current = _items[index];
    if (!current.isPending) throw StateError('Already decided');

    final updated = BusinessRegistration(
      id: current.id,
      name: current.name,
      businessType: current.businessType,
      phone: current.phone,
      status: approved ? 'active' : 'rejected',
      createdAt: current.createdAt,
      currency: current.currency,
      ownerName: current.ownerName,
      ownerPhone: current.ownerPhone,
      rejectionReason: reason,
      approvedAt: approved ? DateTime.now() : null,
      rejectedAt: approved ? null : DateTime.now(),
    );
    _items[index] = updated;
    return updated;
  }
}

final registrationQueueRepositoryProvider = Provider<RegistrationQueueRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiRegistrationQueueRepository(ref.watch(apiClientProvider)),
    AppMode.demo => DemoRegistrationQueueRepository(),
  };
});

/// The pending queue, refetched whenever a decision invalidates it.
final pendingRegistrationsProvider = FutureProvider<List<BusinessRegistration>>((ref) async {
  final repo = ref.watch(registrationQueueRepositoryProvider);
  final result = await repo.list(const PagedQuery(pageSize: 100), status: 'pending');
  return result.items;
});
