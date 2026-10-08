import 'dart:typed_data';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import '../../../core/error/failure.dart';
import 'audit_models.dart';

abstract class AuditRepository {
  Future<PaginatedResult<AuditLogEntry>> list(PagedQuery query);

  /// One entry as §28's document, rendered by the server from the row as
  /// recorded. The trail is evidence; a printed copy is what gets attached to a
  /// dispute, so it comes from the record rather than from this screen.
  Future<Uint8List> entryPdf(String id);
}

class LocalAuditRepository with DemoRepository implements AuditRepository {
  final List<AuditLogEntry> _items = _seed();

  static List<AuditLogEntry> _seed() {
    final now = DateTime.now();
    return [
      AuditLogEntry(id: 'aud-1', userName: 'Demo Admin', action: 'login', module: 'auth', description: 'Signed in', ipAddress: '10.0.0.4', createdAt: now.subtract(const Duration(hours: 1))),
      AuditLogEntry(id: 'aud-2', userName: 'Demo Admin', action: 'product.create', module: 'products', description: 'Created product "Bookshelf — 5 Tier"', ipAddress: '10.0.0.4', createdAt: now.subtract(const Duration(hours: 3))),
      AuditLogEntry(id: 'aud-3', userName: 'Zana Hussein', action: 'inventory.adjust', module: 'inventory', description: 'Adjusted stock for "Ergonomic Office Chair" (+10)', ipAddress: '10.0.0.9', createdAt: now.subtract(const Duration(hours: 5))),
      AuditLogEntry(id: 'aud-4', userName: 'Dilan Omar', action: 'sale.create', module: 'sales', description: 'Created sale SALE-2026-000002', ipAddress: '10.0.0.12', createdAt: now.subtract(const Duration(hours: 6))),
      AuditLogEntry(id: 'aud-5', userName: 'Demo Admin', action: 'category.create', module: 'categories', description: 'Created category "Discontinued Line"', ipAddress: '10.0.0.4', createdAt: now.subtract(const Duration(days: 1))),
      AuditLogEntry(id: 'aud-6', userName: 'Demo Admin', action: 'settings.change', module: 'settings', description: 'Updated PDF footer text', ipAddress: '10.0.0.4', createdAt: now.subtract(const Duration(days: 2))),
      AuditLogEntry(id: 'aud-7', userName: 'Rezan Ali', action: 'purchase.create', module: 'purchases', description: 'Created purchase PUR-2026-000001', ipAddress: '10.0.0.15', createdAt: now.subtract(const Duration(days: 5))),
    ];
  }

  @override
  Future<PaginatedResult<AuditLogEntry>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<AuditLogEntry>.from(_items)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final module = query.filters['module'] as String?;
    if (module != null) pool = pool.where((e) => e.module == module).toList();
    final userName = query.filters['userName'] as String?;
    if (userName != null) pool = pool.where((e) => e.userName == userName).toList();
    return paginateInMemory<AuditLogEntry>(pool, query, matches: (item, q) => item.description.toLowerCase().contains(q) || item.userName.toLowerCase().contains(q));
  }

  /// Demo mode has no PDF engine — the document is rendered by the server, from
  /// the row as recorded. Refusing is the honest answer; producing a plausible
  /// file here would be a document this system never actually issued.
  @override
  Future<Uint8List> entryPdf(String id) async {
    await simulatedLatency();
    throw const Failure(
      'DEMO_MODE',
      'Documents are produced by the server. Connect a backend to download this record.',
    );
  }
}
