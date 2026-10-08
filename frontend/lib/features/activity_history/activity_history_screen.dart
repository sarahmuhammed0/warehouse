import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/pagination/pagination_bar.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import 'data/audit_models.dart';
import 'presentation/activity_entry_dialog.dart';
import 'data/audit_providers.dart';

/// Activity History / audit log (spec §28/§30) — the same shape the
/// backend's real `audit_logs` table + `writeAuditLog` writer (Phase 2)
/// already use for auth events; this screen is ready for that data the
/// moment `AuditRepository` gets a real implementation.
class ActivityHistoryPlaceholderScreen extends ConsumerWidget {
  const ActivityHistoryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(auditListControllerProvider);
    final controller = ref.read(auditListControllerProvider.notifier);

    final columns = <AppTableColumn<AuditLogEntry>>[
      AppTableColumn(label: l10n.fieldEmployee, cellBuilder: (context, item) => Text(item.userName)),
      AppTableColumn(label: l10n.fieldModule, cellBuilder: (context, item) => Text(item.module)),
      AppTableColumn(label: l10n.details, cellBuilder: (context, item) => Text(item.description)),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(_formatDateTime(item.createdAt))),
      AppTableColumn(label: l10n.fieldIpAddress, showInMobileCard: false, cellBuilder: (context, item) => Text(item.ipAddress ?? '—')),
    ];

    return PageScaffold(
      title: l10n.navActivityHistory,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      searchBar: SizedBox(width: 280, child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: controller.search)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppDataTable<AuditLogEntry>(
            columns: columns,
            rows: state.items,
            idOf: (item) => item.id,
            // The table shows four columns because a table has to fit. Opening
            // a row gives the rest of the record — the actor, the reference,
            // the address — and the option to file it as a document.
            onRowTap: (item) => showActivityEntryDialog(context, item),
            loading: state.loading,
            errorMessage: state.error,
            onRetry: controller.reload,
            emptyTitle: l10n.emptyStateDefaultTitle,
          ),
          if (!state.loading && state.error == null)
            PaginationBar(page: state.query.page, totalPages: state.totalPages, pageSize: state.query.pageSize, pageSizeOptions: const [10, 20, 50], onPageChanged: controller.changePage, onPageSizeChanged: controller.changePageSize),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
