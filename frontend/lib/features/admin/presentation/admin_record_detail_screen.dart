import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../../employees/data/employee_models.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../orders/orders_screen.dart' show orderStatusLabel, orderStatusTone;
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../data/admin_providers.dart';
import 'admin_metric.dart';

/// **Level 4** of the System Admin drill-down: one record, read-only.
///
/// Deliberately not the business app's own detail screen. Those screens
/// carry Edit/Delete/status-transition actions belonging to the business's
/// staff; a platform admin looking at a tenant's record is overseeing it,
/// not operating it. Reusing them here would also mean an admin's Edit
/// button pushing a business-shell route their session is redirected out of
/// (see `app_router.dart`'s redirect) — a dead end shown as a live control.
///
/// The data itself is *not* duplicated: this reads the same providers the
/// business modules read (`productByIdProvider`, `orderByIdProvider`) and,
/// for employees, the by-id method added alongside them.
class AdminRecordDetailScreen extends ConsumerWidget {
  const AdminRecordDetailScreen({super.key, required this.metric, required this.businessId, required this.recordId});

  final AdminMetric metric;
  final String businessId;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (metric) {
      AdminMetric.employees => _EmployeeDetail(metric: metric, businessId: businessId, recordId: recordId),
      AdminMetric.products => _ProductDetail(metric: metric, businessId: businessId, recordId: recordId),
      AdminMetric.orders || AdminMetric.sales => _OrderDetail(metric: metric, businessId: businessId, recordId: recordId),
    };
  }
}

/// One page shape for all four record types: title + a card of labelled
/// rows. Keeps the back arrow, fallback route and loading/error handling
/// identical across the drill-down instead of three near-copies.
class _RecordScaffold extends StatelessWidget {
  const _RecordScaffold({required this.metric, required this.businessId, required this.title, required this.rows, this.status});

  final AdminMetric metric;
  final String businessId;
  final String title;
  final List<(String, String)> rows;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PageScaffold(
      title: title,
      subtitle: metric.label(l10n),
      showBackButton: true,
      backFallbackRoute: metric.recordsRoute(businessId),
      body: AppCard(
        title: Text(l10n.details),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            for (final (label, value) in rows)
              Row(
                children: [
                  Expanded(child: Text(label, style: AppTypography.label)),
                  Expanded(child: Text(value, style: AppTypography.bodyStrong, overflow: TextOverflow.ellipsis)),
                ],
              ),
            if (status != null)
              Row(
                children: [
                  Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                  Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: status!)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.metric, required this.businessId, this.onRetry});
  final AdminMetric metric;
  final String businessId;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PageScaffold(
      title: l10n.details,
      showBackButton: true,
      backFallbackRoute: metric.recordsRoute(businessId),
      body: onRetry == null
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          : AppErrorState(message: l10n.unableToLoad, onRetry: onRetry!),
    );
  }
}

class _EmployeeDetail extends ConsumerWidget {
  const _EmployeeDetail({required this.metric, required this.businessId, required this.recordId});
  final AdminMetric metric;
  final String businessId;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminEmployeeByIdProvider(recordId));
    return async.when(
      loading: () => _Pending(metric: metric, businessId: businessId),
      error: (_, _) => _Pending(metric: metric, businessId: businessId, onRetry: () => ref.invalidate(adminEmployeeByIdProvider(recordId))),
      data: (employee) => _RecordScaffold(
        metric: metric,
        businessId: businessId,
        title: employee.name,
        rows: [
          (l10n.fieldPhone, employee.phone),
          (l10n.fieldEmail, employee.email ?? '—'),
          (l10n.fieldRole, employee.roleName),
          (l10n.fieldCreatedAt, _date(employee.createdAt)),
        ],
        status: StatusBadge(
          label: employee.status == EmployeeStatus.active ? l10n.statusActive : l10n.statusInactive,
          tone: employee.status == EmployeeStatus.active ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    );
  }
}

class _ProductDetail extends ConsumerWidget {
  const _ProductDetail({required this.metric, required this.businessId, required this.recordId});
  final AdminMetric metric;
  final String businessId;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(productByIdProvider(recordId));
    return async.when(
      loading: () => _Pending(metric: metric, businessId: businessId),
      error: (_, _) => _Pending(metric: metric, businessId: businessId, onRetry: () => ref.invalidate(productByIdProvider(recordId))),
      data: (product) => _RecordScaffold(
        metric: metric,
        businessId: businessId,
        title: product.name,
        rows: [
          (l10n.fieldCode, product.code),
          (l10n.fieldSku, product.sku ?? '—'),
          (l10n.fieldCategory, product.categoryName),
          (l10n.fieldQuantity, '${product.currentQuantity} ${product.unit}'),
          (l10n.fieldLocation, product.shelfRackBin ?? '—'),
          (l10n.fieldPurchaseCost, product.purchaseCost?.toStringAsFixed(2) ?? '—'),
          (l10n.fieldSellingPrice, product.sellingPrice?.toStringAsFixed(2) ?? '—'),
        ],
        status: StatusBadge(
          label: switch (product.status) {
            ProductStatus.active => l10n.statusActive,
            ProductStatus.inactive => l10n.statusInactive,
            ProductStatus.discontinued => l10n.statusCancelled,
          },
          tone: switch (product.status) {
            ProductStatus.active => StatusTone.success,
            ProductStatus.inactive => StatusTone.neutral,
            ProductStatus.discontinued => StatusTone.danger,
          },
        ),
      ),
    );
  }
}

class _OrderDetail extends ConsumerWidget {
  const _OrderDetail({required this.metric, required this.businessId, required this.recordId});
  final AdminMetric metric;
  final String businessId;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(orderByIdProvider(recordId));
    return async.when(
      loading: () => _Pending(metric: metric, businessId: businessId),
      error: (_, _) => _Pending(metric: metric, businessId: businessId, onRetry: () => ref.invalidate(orderByIdProvider(recordId))),
      data: (order) => _RecordScaffold(
        metric: metric,
        businessId: businessId,
        title: order.orderNumber,
        rows: [
          (l10n.fieldCustomer, order.customerName ?? '—'),
          (l10n.fieldDate, _date(order.createdAt)),
          (l10n.fieldCreatedBy, order.createdBy),
          (l10n.fieldSubtotal, order.subtotal.toStringAsFixed(2)),
          (l10n.fieldGrandTotal, order.grandTotal.toStringAsFixed(2)),
          (l10n.fieldPaymentStatus, _paymentStatus(l10n, order.paymentStatus)),
          for (final item in order.items) (item.productName, '${item.quantity} × ${item.unitPrice.toStringAsFixed(2)}'),
        ],
        status: StatusBadge(label: orderStatusLabel(l10n, order.status), tone: orderStatusTone(order.status)),
      ),
    );
  }
}

String _date(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String _paymentStatus(AppLocalizations l10n, PaymentStatus status) => switch (status) {
      PaymentStatus.paid => l10n.statusPaid,
      PaymentStatus.partiallyPaid => l10n.statusPartiallyPaid,
      PaymentStatus.unpaid => l10n.statusUnpaid,
    };
