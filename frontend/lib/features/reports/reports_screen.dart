import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../orders/data/order_models.dart';
import '../orders/data/order_providers.dart';
import '../orders/orders_screen.dart' show orderStatusLabel, orderStatusTone;
import '../products/data/product_models.dart';
import '../products/data/product_providers.dart';

/// Reports (spec §25/§26) — Operational vs. Business report areas, each a
/// card grid of report types. "Current Inventory" and "Sales" are wired to
/// real (demo-repository) data to prove the pattern end-to-end; the rest
/// are real, navigable cards whose filter/export chrome is built but whose
/// data queries are deferred — see `docs/frontend-coverage.md`.
class ReportsPlaceholderScreen extends StatefulWidget {
  const ReportsPlaceholderScreen({super.key});

  @override
  State<ReportsPlaceholderScreen> createState() => _ReportsPlaceholderScreenState();
}

class _ReportsPlaceholderScreenState extends State<ReportsPlaceholderScreen> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);
  String? _openReport;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_openReport == 'inventory') return _CurrentInventoryReport(onBack: () => setState(() => _openReport = null));
    if (_openReport == 'sales') return _SalesReport(onBack: () => setState(() => _openReport = null));

    return PageScaffold(
      title: l10n.navReports,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          TabBar(controller: _tabController, tabs: const [Tab(text: 'Operational'), Tab(text: 'Business')]),
          SizedBox(
            height: 420,
            child: TabBarView(
              controller: _tabController,
              children: [
                _ReportGrid(
                  reports: [
                    ('inventory', Icons.inventory_2_outlined, l10n.navInventory, () => setState(() => _openReport = 'inventory')),
                    ('movement', Icons.swap_vert, 'Stock movement', null),
                    ('production', Icons.precision_manufacturing_outlined, l10n.navProduction, null),
                    ('purchases', Icons.shopping_cart_outlined, l10n.navPurchases, null),
                    ('transfers', Icons.local_shipping_outlined, l10n.transfer, null),
                    ('returns', Icons.assignment_return_outlined, l10n.navReturns, null),
                  ],
                ),
                _ReportGrid(
                  reports: [
                    ('sales', Icons.point_of_sale_outlined, l10n.navSales, () => setState(() => _openReport = 'sales')),
                    ('revenue', Icons.trending_up, 'Revenue', null),
                    ('costs', Icons.trending_down, 'Costs', null),
                    ('profit', Icons.attach_money, 'Profit', null),
                    ('customers', Icons.people_outline, l10n.navCustomers, null),
                    ('outstanding', Icons.account_balance_wallet_outlined, l10n.fieldOutstandingBalance, null),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportGrid extends StatelessWidget {
  const _ReportGrid({required this.reports});
  final List<(String, IconData, String, VoidCallback?)> reports;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: [
        for (final (_, icon, label, onTap) in reports)
          AppCard(
            child: InkWell(
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28),
                  const SizedBox(height: 8),
                  Text(label, textAlign: TextAlign.center, style: AppTypography.bodyStrong),
                  if (onTap == null) Text('Coming soon', style: AppTypography.caption),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrentInventoryReport extends ConsumerWidget {
  const _CurrentInventoryReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final productsAsync = ref.watch(productPickerOptionsProvider);
    final columns = <AppTableColumn<Product>>[
      AppTableColumn(label: l10n.fieldName, cellBuilder: (context, item) => Text(item.name)),
      AppTableColumn(label: l10n.fieldCategory, cellBuilder: (context, item) => Text(item.categoryName)),
      AppTableColumn(label: l10n.fieldCurrentQuantity, numeric: true, cellBuilder: (context, item) => Text('${item.currentQuantity}')),
      AppTableColumn(label: l10n.fieldPurchaseCost, numeric: true, cellBuilder: (context, item) => Text(((item.purchaseCost ?? 0) * item.currentQuantity).toStringAsFixed(2))),
    ];
    return PageScaffold(
      title: '${l10n.navReports} — ${l10n.navInventory}',
      secondaryActions: [
        AppButton(label: l10n.back, variant: AppButtonVariant.text, onPressed: onBack),
        AppButton(label: l10n.export, icon: Icons.download, variant: AppButtonVariant.outline, onPressed: () {}),
      ],
      body: productsAsync.when(
        data: (products) => AppDataTable<Product>(columns: columns, rows: products, idOf: (p) => p.id, emptyTitle: l10n.emptyStateDefaultTitle),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.unableToLoad)),
      ),
    );
  }
}

class _SalesReport extends ConsumerWidget {
  const _SalesReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(orderListControllerProvider);
    final columns = <AppTableColumn<Order>>[
      AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (context, item) => Text(item.orderNumber)),
      AppTableColumn(label: l10n.fieldDate, cellBuilder: (context, item) => Text(item.createdAt.toString().split(' ').first)),
      AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (context, item) => Text(item.grandTotal.toStringAsFixed(2))),
      AppTableColumn(label: l10n.fieldStatus, cellBuilder: (context, item) => StatusBadge(label: orderStatusLabel(l10n, item.status), tone: orderStatusTone(item.status))),
    ];
    final total = state.items.fold<double>(0, (sum, o) => sum + o.grandTotal);
    return PageScaffold(
      title: '${l10n.navReports} — ${l10n.navSales}',
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      secondaryActions: [
        AppButton(label: l10n.back, variant: AppButtonVariant.text, onPressed: onBack),
        AppButton(label: l10n.export, icon: Icons.download, variant: AppButtonVariant.outline, onPressed: () {}),
      ],
      body: AppDataTable<Order>(columns: columns, rows: state.items, idOf: (o) => o.id, loading: state.loading, emptyTitle: l10n.emptyStateDefaultTitle),
    );
  }
}
