import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/network/providers.dart';
import '../../../core/repositories/paged_list_controller.dart';
import '../../../core/repositories/paged_query.dart';
import 'api_audit_repository.dart';
import 'audit_models.dart';
import 'audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiAuditRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalAuditRepository(),
  };
});

final auditListControllerProvider =
    NotifierProvider<AuditListController, PagedListState<AuditLogEntry>>(AuditListController.new);

class AuditListController extends PagedListController<AuditLogEntry> {
  @override
  Future<PaginatedResult<AuditLogEntry>> fetch(PagedQuery query) {
    return ref.read(auditRepositoryProvider).list(query);
  }
}
