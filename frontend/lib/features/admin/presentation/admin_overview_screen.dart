import '../../settings/data/business_type_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/tables/app_data_table.dart';
import '../../../shared/tables/table_column.dart';
import '../../../shared/tables/table_row_actions.dart';
import '../data/admin_business_models.dart';
import '../data/admin_metrics.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';

/// **Level 2** of the System Admin drill-down: one row per business, with
/// that business's own count for the metric the admin tapped.
///
/// This is the screen that makes the rule in the brief true — "the System
/// Admin must never be dropped directly into a warehouse's operational
/// table just because they tapped a platform statistic". Tapping *Products*
/// on the dashboard lands here, showing how the platform total splits
/// across businesses; only after explicitly choosing one does the admin see
/// that business's product rows.
///
/// The counts are not stored anywhere: `adminMetricsProvider` derives them
/// from the same `listForBusiness` calls Level 3 uses to build its table, so
/// the number on a row is by construction the number of rows behind it.
class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key, required this.metric});

  final AdminMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final businessesState = ref.watch(adminBusinessListControllerProvider);
    final metricsAsync = ref.watch(adminMetricsProvider);

    return PageScaffold(
      title: metric.label(l10n),
      subtitle: l10n.adminSelectBusiness,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminDashboard,
      body: metricsAsync.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        error: (_, _) => AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminMetricsProvider)),
        data: (metrics) {
          final businesses = businessesState.items;
          final columns = <AppTableColumn<AdminBusiness>>[
            AppTableColumn(label: l10n.fieldBusiness, cellBuilder: (context, item) => Text(item.name)),
            AppTableColumn(label: l10n.fieldBusinessType, cellBuilder: (context, item) => Text(businessTypeLabelFor(item.businessType))),
            AppTableColumn(
              label: l10n.fieldStatus,
              cellBuilder: (context, item) => StatusBadge(
                label: item.status == BusinessAccountStatus.active ? l10n.statusActive : l10n.statusDisabled,
                tone: item.status == BusinessAccountStatus.active ? StatusTone.success : StatusTone.danger,
              ),
            ),
            if (metric == AdminMetric.sales)
              AppTableColumn(
                label: l10n.fieldGrandTotal,
                numeric: true,
                cellBuilder: (context, item) => Text(metrics.forBusiness(item.id).salesTotal.toStringAsFixed(2)),
              ),
            AppTableColumn(
              label: metric.label(l10n),
              numeric: true,
              cellBuilder: (context, item) => Text('${metric.countFor(metrics.forBusiness(item.id))}'),
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              AppDataTable<AdminBusiness>(
                columns: columns,
                rows: businesses,
                idOf: (item) => item.id,
                loading: businessesState.loading,
                errorMessage: businessesState.error,
                onRetry: ref.read(adminBusinessListControllerProvider.notifier).reload,
                emptyTitle: l10n.emptyStateDefaultTitle,
                onRowTap: (item) => context.push(metric.recordsRoute(item.id)),
                rowActionsBuilder: (context, item) => TableRowActions(
                  actions: [
                    RowAction(
                      label: l10n.view,
                      icon: Icons.visibility_outlined,
                      onTap: () => context.push(metric.recordsRoute(item.id)),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
