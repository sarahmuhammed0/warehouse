import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/tables/app_data_table.dart';
import '../../shared/tables/table_column.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../auth/presentation/providers/permission_providers.dart';
import '../customers/data/customer_models.dart';
import '../customers/data/customer_providers.dart';
import '../inventory/data/inventory_models.dart';
import '../inventory/data/inventory_providers.dart';
import '../orders/data/order_models.dart';
import '../orders/data/order_providers.dart';
import '../orders/orders_screen.dart' show orderStatusLabel, orderStatusTone;
import '../production/data/production_models.dart';
import '../production/data/production_providers.dart';
import '../products/data/product_models.dart';
import '../products/data/product_providers.dart';
import '../purchases/data/purchase_models.dart';
import '../purchases/data/purchase_providers.dart';
import '../returns/data/return_models.dart';
import '../returns/data/return_providers.dart';
import 'presentation/report_export.dart';

/// Reports (spec §25/§26) — Operational and Business report areas.
///
/// Every card here opens a real report over real demo data. Ten of the
/// twelve used to pass `onTap: null` and render "Coming soon" while the
/// provider each one needed already existed and was already being read
/// elsewhere in the app; the two that did open had Export buttons wired to
/// `onPressed: () {}`, which renders as a fully enabled button that
/// silently does nothing.
///
/// Every report shares [_ReportView], so filtering, the row count, the
/// empty state and Export behave identically across all twelve rather than
/// twelve times differently.
enum _Report {
  inventory,
  stockMovement,
  production,
  purchases,
  transfers,
  returns,
  sales,
  revenue,
  costs,
  profit,
  customers,
  outstanding,
}

class ReportsPlaceholderScreen extends StatefulWidget {
  const ReportsPlaceholderScreen({super.key});

  @override
  State<ReportsPlaceholderScreen> createState() => _ReportsPlaceholderScreenState();
}

class _ReportsPlaceholderScreenState extends State<ReportsPlaceholderScreen> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);
  _Report? _open;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _close() => setState(() => _open = null);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_open != null) {
      return switch (_open!) {
        _Report.inventory => _InventoryReport(onBack: _close),
        _Report.stockMovement => _StockMovementReport(onBack: _close),
        _Report.production => _ProductionReport(onBack: _close),
        _Report.purchases => _PurchasesReport(onBack: _close),
        _Report.transfers => _TransfersReport(onBack: _close),
        _Report.returns => _ReturnsReport(onBack: _close),
        _Report.sales => _SalesReport(onBack: _close),
        _Report.revenue => _RevenueReport(onBack: _close),
        _Report.costs => _CostsReport(onBack: _close),
        _Report.profit => _ProfitReport(onBack: _close),
        _Report.customers => _CustomersReport(onBack: _close),
        _Report.outstanding => _OutstandingReport(onBack: _close),
      };
    }

    void open(_Report report) => setState(() => _open = report);

    return PageScaffold(
      title: l10n.navReports,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
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
                    (Icons.inventory_2_outlined, l10n.navInventory, () => open(_Report.inventory)),
                    (Icons.swap_vert, l10n.reportStockMovement, () => open(_Report.stockMovement)),
                    (Icons.precision_manufacturing_outlined, l10n.navProduction, () => open(_Report.production)),
                    (Icons.shopping_cart_outlined, l10n.navPurchases, () => open(_Report.purchases)),
                    (Icons.local_shipping_outlined, l10n.transfer, () => open(_Report.transfers)),
                    (Icons.assignment_return_outlined, l10n.navReturns, () => open(_Report.returns)),
                  ],
                ),
                _ReportGrid(
                  reports: [
                    (Icons.point_of_sale_outlined, l10n.navSales, () => open(_Report.sales)),
                    (Icons.trending_up, l10n.reportRevenue, () => open(_Report.revenue)),
                    (Icons.trending_down, l10n.reportCosts, () => open(_Report.costs)),
                    (Icons.attach_money, l10n.reportProfit, () => open(_Report.profit)),
                    (Icons.people_outline, l10n.navCustomers, () => open(_Report.customers)),
                    (Icons.account_balance_wallet_outlined, l10n.reportOutstanding, () => open(_Report.outstanding)),
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
  final List<(IconData, String, VoidCallback)> reports;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: [
        for (final (icon, label, onTap) in reports)
          AppCard(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: AppTypography.bodyStrong),
              ],
            ),
          ),
      ],
    );
  }
}

/// The one report shell: title, optional total, a search box that really
/// narrows the rows, a live row count, Back, and an Export that produces
/// the actual CSV for exactly the rows on screen (not the unfiltered set).
class _ReportView<T> extends StatefulWidget {
  const _ReportView({
    required this.title,
    required this.onBack,
    required this.columns,
    required this.rows,
    required this.idOf,
    required this.searchText,
    required this.csvRow,
    this.subtitle,
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final String Function(T) idOf;

  /// What the report's search box matches against.
  final String Function(T) searchText;

  /// One CSV line per row, in the same order as [columns].
  final List<String> Function(T) csvRow;
  final bool loading;

  @override
  State<_ReportView<T>> createState() => _ReportViewState<T>();
}

class _ReportViewState<T> extends State<_ReportView<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty ? widget.rows : widget.rows.where((r) => widget.searchText(r).toLowerCase().contains(query)).toList();

    return Consumer(
      builder: (context, ref, _) {
        final canExport = hasPermission(ref.watch(currentPermissionsProvider), 'reports', 'export');
        return PageScaffold(
          title: '${l10n.navReports} — ${widget.title}',
          subtitle: widget.subtitle,
          searchBar: SizedBox(
            width: 280,
            child: AppTextField(label: l10n.search, hintText: l10n.searchPlaceholder, onChanged: (v) => setState(() => _query = v)),
          ),
          secondaryActions: [
            AppButton(label: l10n.back, variant: AppButtonVariant.text, onPressed: widget.onBack),
            if (canExport)
              AppButton(
                key: const ValueKey('reportExport'),
                label: l10n.exportCsv,
                icon: Icons.download,
                variant: AppButtonVariant.outline,
                onPressed: () => showExportPreview(
                  context,
                  title: widget.title,
                  headers: [for (final c in widget.columns) c.label],
                  rows: [for (final r in rows) widget.csvRow(r)],
                ),
              ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              Text(l10n.totalRecords(rows.length), style: AppTypography.caption),
              AppDataTable<T>(
                columns: widget.columns,
                rows: rows,
                idOf: widget.idOf,
                loading: widget.loading,
                emptyTitle: l10n.emptyStateDefaultTitle,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Operational
// ---------------------------------------------------------------------------

class _InventoryReport extends ConsumerWidget {
  const _InventoryReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(productPickerOptionsProvider);
    final products = async.asData?.value ?? const <Product>[];
    final valuation = products.fold<double>(0, (sum, p) => sum + ((p.purchaseCost ?? 0) * p.currentQuantity));

    return _ReportView<Product>(
      title: l10n.navInventory,
      subtitle: '${l10n.fieldPurchaseCost}: ${valuation.toStringAsFixed(2)}',
      onBack: onBack,
      loading: async.isLoading,
      rows: products,
      idOf: (p) => p.id,
      searchText: (p) => '${p.name} ${p.categoryName} ${p.sku ?? ''}',
      columns: [
        AppTableColumn(label: l10n.fieldName, cellBuilder: (c, p) => Text(p.name)),
        AppTableColumn(label: l10n.fieldCategory, cellBuilder: (c, p) => Text(p.categoryName)),
        AppTableColumn(label: l10n.fieldCurrentQuantity, numeric: true, cellBuilder: (c, p) => Text('${p.currentQuantity}')),
        AppTableColumn(label: l10n.fieldPurchaseCost, numeric: true, cellBuilder: (c, p) => Text(((p.purchaseCost ?? 0) * p.currentQuantity).toStringAsFixed(2))),
      ],
      csvRow: (p) => [p.name, p.categoryName, '${p.currentQuantity}', ((p.purchaseCost ?? 0) * p.currentQuantity).toStringAsFixed(2)],
    );
  }
}

class _StockMovementReport extends ConsumerWidget {
  const _StockMovementReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(movementListControllerProvider);

    return _ReportView<StockMovement>(
      title: l10n.reportStockMovement,
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (m) => m.id,
      searchText: (m) => '${m.productName} ${m.type.name} ${m.userName}',
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, m) => Text(_date(m.dateTime))),
        AppTableColumn(label: l10n.fieldProduct, cellBuilder: (c, m) => Text(m.productName)),
        AppTableColumn(label: l10n.fieldModule, cellBuilder: (c, m) => Text(m.type.name)),
        AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (c, m) => Text('${m.previousQuantity} → ${m.newQuantity}')),
        AppTableColumn(label: l10n.fieldCreatedBy, cellBuilder: (c, m) => Text(m.userName)),
      ],
      csvRow: (m) => [_date(m.dateTime), m.productName, m.type.name, '${m.previousQuantity} -> ${m.newQuantity}', m.userName],
    );
  }
}

class _ProductionReport extends ConsumerWidget {
  const _ProductionReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(productionListControllerProvider);

    return _ReportView<ProductionOrder>(
      title: l10n.navProduction,
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (p) => p.id,
      searchText: (p) => '${p.productionNumber} ${p.productName}',
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, p) => Text(_date(p.createdAt))),
        AppTableColumn(label: l10n.fieldProduct, cellBuilder: (c, p) => Text(p.productName)),
        AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (c, p) => Text('${p.quantityProduced}/${p.quantityPlanned}')),
        AppTableColumn(label: l10n.fieldStatus, cellBuilder: (c, p) => Text(p.status.name)),
      ],
      csvRow: (p) => [_date(p.createdAt), p.productName, '${p.quantityProduced}/${p.quantityPlanned}', p.status.name],
    );
  }
}

class _PurchasesReport extends ConsumerWidget {
  const _PurchasesReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(purchaseListControllerProvider);
    final total = state.items.fold<double>(0, (sum, p) => sum + p.total);

    return _ReportView<Purchase>(
      title: l10n.navPurchases,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (p) => p.id,
      searchText: (p) => '${p.purchaseNumber} ${p.supplierName}',
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, p) => Text(_date(p.createdAt))),
        AppTableColumn(label: l10n.fieldSupplier, cellBuilder: (c, p) => Text(p.supplierName)),
        AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (c, p) => Text(p.total.toStringAsFixed(2))),
        AppTableColumn(label: l10n.fieldStatus, cellBuilder: (c, p) => Text(p.status.name)),
      ],
      csvRow: (p) => [_date(p.createdAt), p.supplierName, p.total.toStringAsFixed(2), p.status.name],
    );
  }
}

class _TransfersReport extends ConsumerWidget {
  const _TransfersReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(transferListControllerProvider);

    return _ReportView<StockTransfer>(
      title: l10n.transfer,
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (t) => t.id,
      searchText: (t) => '${t.transferNumber} ${t.productName} ${t.fromWarehouse} ${t.toWarehouse}',
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, t) => Text(_date(t.createdAt))),
        AppTableColumn(label: l10n.fieldProduct, cellBuilder: (c, t) => Text(t.productName)),
        AppTableColumn(label: l10n.fieldLocation, cellBuilder: (c, t) => Text('${t.fromWarehouse} → ${t.toWarehouse}')),
        AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (c, t) => Text('${t.quantity}')),
        AppTableColumn(label: l10n.fieldStatus, cellBuilder: (c, t) => Text(t.status.name)),
      ],
      csvRow: (t) => [_date(t.createdAt), t.productName, '${t.fromWarehouse} -> ${t.toWarehouse}', '${t.quantity}', t.status.name],
    );
  }
}

class _ReturnsReport extends ConsumerWidget {
  const _ReturnsReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(returnListControllerProvider);
    final refunded = state.items.fold<double>(0, (sum, r) => sum + r.refundAmount);

    return _ReportView<ProductReturn>(
      title: l10n.navReturns,
      subtitle: '${l10n.fieldRemainingAmount}: ${refunded.toStringAsFixed(2)}',
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (r) => r.id,
      searchText: (r) => '${r.returnNumber} ${r.orderNumber} ${r.customerName ?? ''} ${r.reason}',
      columns: [
        AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (c, r) => Text(r.returnNumber)),
        AppTableColumn(label: l10n.fieldCustomer, cellBuilder: (c, r) => Text(r.customerName ?? '—')),
        AppTableColumn(label: l10n.fieldReason, cellBuilder: (c, r) => Text(r.reason)),
        AppTableColumn(label: l10n.fieldRemainingAmount, numeric: true, cellBuilder: (c, r) => Text(r.refundAmount.toStringAsFixed(2))),
        AppTableColumn(label: l10n.fieldStatus, cellBuilder: (c, r) => Text(r.status.name)),
      ],
      csvRow: (r) => [r.returnNumber, r.customerName ?? '', r.reason, r.refundAmount.toStringAsFixed(2), r.status.name],
    );
  }
}

// ---------------------------------------------------------------------------
// Business
// ---------------------------------------------------------------------------

class _SalesReport extends ConsumerWidget {
  const _SalesReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(orderListControllerProvider);
    final total = state.items.fold<double>(0, (sum, o) => sum + o.grandTotal);

    return _ReportView<Order>(
      title: l10n.navSales,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (o) => o.id,
      searchText: (o) => '${o.orderNumber} ${o.customerName ?? ''}',
      columns: [
        AppTableColumn(label: l10n.fieldOrderNumber, cellBuilder: (c, o) => Text(o.orderNumber)),
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, o) => Text(_date(o.createdAt))),
        AppTableColumn(label: l10n.fieldGrandTotal, numeric: true, cellBuilder: (c, o) => Text(o.grandTotal.toStringAsFixed(2))),
        AppTableColumn(label: l10n.fieldStatus, cellBuilder: (c, o) => StatusBadge(label: orderStatusLabel(l10n, o.status), tone: orderStatusTone(o.status))),
      ],
      csvRow: (o) => [o.orderNumber, _date(o.createdAt), o.grandTotal.toStringAsFixed(2), o.status.name],
    );
  }
}

/// One row per month — revenue, in the same fold the dashboard's chart uses.
class _MonthlyRow {
  const _MonthlyRow(this.label, this.revenue, this.cost);
  final String label;
  final double revenue;
  final double cost;
  double get profit => revenue - cost;
}

List<_MonthlyRow> _monthlyRows(WidgetRef ref) {
  final orders = ref.watch(orderListControllerProvider).items;
  final purchases = ref.watch(purchaseListControllerProvider).items;
  final now = DateTime.now();
  return [
    for (var i = 5; i >= 0; i--)
      () {
        final month = DateTime(now.year, now.month - i);
        bool inMonth(DateTime d) => d.year == month.year && d.month == month.month;
        return _MonthlyRow(
          '${month.month}/${month.year}',
          orders.where((o) => inMonth(o.createdAt)).fold<double>(0, (s, o) => s + o.grandTotal),
          purchases.where((p) => inMonth(p.createdAt)).fold<double>(0, (s, p) => s + p.total),
        );
      }(),
  ];
}

class _RevenueReport extends ConsumerWidget {
  const _RevenueReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rows = _monthlyRows(ref);
    final total = rows.fold<double>(0, (s, r) => s + r.revenue);

    return _ReportView<_MonthlyRow>(
      title: l10n.reportRevenue,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      rows: rows,
      idOf: (r) => r.label,
      searchText: (r) => r.label,
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, r) => Text(r.label)),
        AppTableColumn(label: l10n.reportRevenue, numeric: true, cellBuilder: (c, r) => Text(r.revenue.toStringAsFixed(2))),
      ],
      csvRow: (r) => [r.label, r.revenue.toStringAsFixed(2)],
    );
  }
}

class _CostsReport extends ConsumerWidget {
  const _CostsReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rows = _monthlyRows(ref);
    final total = rows.fold<double>(0, (s, r) => s + r.cost);

    return _ReportView<_MonthlyRow>(
      title: l10n.reportCosts,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      rows: rows,
      idOf: (r) => r.label,
      searchText: (r) => r.label,
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, r) => Text(r.label)),
        AppTableColumn(label: l10n.reportCosts, numeric: true, cellBuilder: (c, r) => Text(r.cost.toStringAsFixed(2))),
      ],
      csvRow: (r) => [r.label, r.cost.toStringAsFixed(2)],
    );
  }
}

class _ProfitReport extends ConsumerWidget {
  const _ProfitReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rows = _monthlyRows(ref);
    final total = rows.fold<double>(0, (s, r) => s + r.profit);

    return _ReportView<_MonthlyRow>(
      title: l10n.reportProfit,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      rows: rows,
      idOf: (r) => r.label,
      searchText: (r) => r.label,
      columns: [
        AppTableColumn(label: l10n.fieldDate, cellBuilder: (c, r) => Text(r.label)),
        AppTableColumn(label: l10n.reportRevenue, numeric: true, cellBuilder: (c, r) => Text(r.revenue.toStringAsFixed(2))),
        AppTableColumn(label: l10n.reportCosts, numeric: true, cellBuilder: (c, r) => Text(r.cost.toStringAsFixed(2))),
        AppTableColumn(label: l10n.reportProfit, numeric: true, cellBuilder: (c, r) => Text(r.profit.toStringAsFixed(2))),
      ],
      csvRow: (r) => [r.label, r.revenue.toStringAsFixed(2), r.cost.toStringAsFixed(2), r.profit.toStringAsFixed(2)],
    );
  }
}

class _CustomersReport extends ConsumerWidget {
  const _CustomersReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(customerListControllerProvider);

    return _ReportView<Customer>(
      title: l10n.navCustomers,
      onBack: onBack,
      loading: state.loading,
      rows: state.items,
      idOf: (c) => c.id,
      searchText: (c) => '${c.fullName} ${c.phone}',
      columns: [
        AppTableColumn(label: l10n.fieldName, cellBuilder: (c, item) => Text(item.fullName)),
        AppTableColumn(label: l10n.fieldPhone, cellBuilder: (c, item) => Text(item.phone)),
        AppTableColumn(label: l10n.fieldTotalPurchases, numeric: true, cellBuilder: (c, item) => Text(item.totalPurchases.toStringAsFixed(2))),
        AppTableColumn(label: l10n.fieldQuantity, numeric: true, cellBuilder: (c, item) => Text('${item.orderCount}')),
      ],
      csvRow: (c) => [c.fullName, c.phone, c.totalPurchases.toStringAsFixed(2), '${c.orderCount}'],
    );
  }
}

class _OutstandingReport extends ConsumerWidget {
  const _OutstandingReport({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(customerListControllerProvider);
    // Only customers who actually owe something — an "outstanding balances"
    // report listing everyone with 0.00 is a list, not a report.
    final rows = state.items.where((c) => c.outstandingBalance > 0).toList();
    final total = rows.fold<double>(0, (s, c) => s + c.outstandingBalance);

    return _ReportView<Customer>(
      title: l10n.reportOutstanding,
      subtitle: '${l10n.fieldGrandTotal}: ${total.toStringAsFixed(2)}',
      onBack: onBack,
      loading: state.loading,
      rows: rows,
      idOf: (c) => c.id,
      searchText: (c) => '${c.fullName} ${c.phone}',
      columns: [
        AppTableColumn(label: l10n.fieldName, cellBuilder: (c, item) => Text(item.fullName)),
        AppTableColumn(label: l10n.fieldPhone, cellBuilder: (c, item) => Text(item.phone)),
        AppTableColumn(label: l10n.reportOutstanding, numeric: true, cellBuilder: (c, item) => Text(item.outstandingBalance.toStringAsFixed(2))),
      ],
      csvRow: (c) => [c.fullName, c.phone, c.outstandingBalance.toStringAsFixed(2)],
    );
  }
}
