import '../../../core/config/data_source_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/download/file_download.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/feedback/confirm_dialog.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/layout/responsive/responsive_layout.dart';
import '../../../theme/app_typography.dart';
import '../data/order_models.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/stock_engine.dart';
import '../data/order_providers.dart';
import '../data/order_stock.dart';
import '../orders_screen.dart' show orderStatusLabel, orderStatusTone;

/// Order detail (§14: "view/edit/change status/cancel/return/reopen/print/
/// PDF"). Status transitions only ever offer [Order.allowedNextStatuses] —
/// the fixed state machine, never an arbitrary jump. Cancellation always
/// goes through [confirmAction] first (§17: "confirmation dialog required
/// before cancelling").
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(orderByIdProvider(orderId));
    final isSale = async.asData?.value.orderType == OrderType.quickSale;

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: isSale ? AppRoutes.sales : AppRoutes.orders,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: isSale ? AppRoutes.sales : AppRoutes.orders,
        body: AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(orderByIdProvider(orderId))),
      ),
      data: (order) => PageScaffold(
        title: order.orderNumber,
        showBackButton: true,
        backFallbackRoute: isSale ? AppRoutes.sales : AppRoutes.orders,
        secondaryActions: [
          // Every record reached from a history list can be filed. The document
          // is rendered by the server from what was STORED, so a reprint of last
          // year's sale still shows last year's names and prices (§55).
          AppButton(
            key: const ValueKey('orderSavePdf'),
            label: l10n.saveAsPdf,
            icon: Icons.picture_as_pdf_outlined,
            variant: AppButtonVariant.outline,
            onPressed: () => _saveAsPdf(context, ref, order),
          ),
          for (final next in order.allowedNextStatuses)
            AppButton(
              label: next == OrderStatus.cancelled ? l10n.cancelAction : orderStatusLabel(l10n, next),
              variant: next == OrderStatus.cancelled ? AppButtonVariant.destructive : AppButtonVariant.outline,
              onPressed: () => _transition(context, ref, order, next),
            ),
        ],
        body: ResponsiveLayout(
          mobile: (context) => Column(spacing: 16, children: _sections(l10n, order)),
          desktop: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              Expanded(flex: 2, child: Column(spacing: 16, children: [_sections(l10n, order)[0]])),
              Expanded(child: Column(spacing: 16, children: _sections(l10n, order).sublist(1))),
            ],
          ),
        ),
      ),
    );
  }

  /// Fetches §28's document and hands it to the browser as a file.
  ///
  /// The screen is a view of the order; the PDF is rendered by the SERVER from
  /// the stored document, and where the two could ever disagree the file is
  /// right — it is the one somebody ends up holding.
  ///
  /// Every failure says what happened. An empty body, a refusal, a network
  /// error: each is reported in its own words rather than as a button that did
  /// nothing, which is the whole reason this is not a bare `try {} catch {}`.
  Future<void> _saveAsPdf(BuildContext context, WidgetRef ref, Order order) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final bytes = await ref.read(orderRepositoryProvider).invoicePdf(order.id);
      if (bytes.isEmpty) {
        if (context.mounted) AppToast.error(context, l10n.unableToLoad);
        return;
      }
      final filename = '${order.orderNumber}.pdf';
      await downloadBytes(bytes: bytes, filename: filename, mimeType: 'application/pdf');
      if (context.mounted) AppToast.success(context, l10n.pdfSaved(filename));
    } on Failure catch (e) {
      if (context.mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (context.mounted) AppToast.error(context, l10n.unableToLoad);
    }
  }

  Future<void> _transition(BuildContext context, WidgetRef ref, Order order, OrderStatus next) async {
    final l10n = AppLocalizations.of(context)!;
    // Returning is a workflow, not a status flip. Flipping the status here
    // left Returns empty while the order claimed to have been returned —
    // and skipped the condition/quantity/refund decisions a return needs
    // before it can restock. Hand off to the return form with this order
    // already selected; `ReturnDetailScreen` sets the order's status when
    // the return completes.
    if (next == OrderStatus.returned || next == OrderStatus.partiallyReturned) {
      context.push('${AppRoutes.returnNew}?orderId=${order.id}');
      return;
    }
    if (next == OrderStatus.cancelled) {
      final confirmed = await confirmAction(
        context,
        title: l10n.deleteConfirmTitle,
        description: '${l10n.fieldOrderNumber}: ${order.orderNumber}. ${l10n.archiveConfirmDescription}',
        confirmLabel: l10n.cancelAction,
        cancelLabel: l10n.back,
        isDestructive: true,
      );
      if (!(confirmed ?? false)) return;
    }
    await ref.read(orderListControllerProvider.notifier).updateStatus(order.id, next);
    ref.invalidate(orderByIdProvider(order.id));

    // Stock follows the status, in both directions. Completing a standard
    // order ships the goods; cancelling one that had already completed puts
    // them back. A quick sale already moved its stock when it was created
    // (it is born Completed), so it must not move again here.
    final alreadyMovedOnCreate = order.orderType == OrderType.quickSale;
    if (!alreadyMovedOnCreate) {
      final engine = ref.read(stockEngineProvider);
      if (next == OrderStatus.completed && order.status != OrderStatus.completed) {
        await engine.apply(stockChangesFor(order), type: MovementType.sale, note: order.orderNumber);
      } else if (next == OrderStatus.cancelled && order.status == OrderStatus.completed) {
        await engine.reverse(stockChangesFor(order), type: MovementType.sale, note: order.orderNumber);
      }
    }
    ref.invalidate(dashboardMetricsProvider);
  }

  List<Widget> _sections(AppLocalizations l10n, Order order) {
    return [
      AppCard(
        title: Text(l10n.fieldProduct),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(item.productName)),
                    Expanded(child: Text('×${item.quantity}', textAlign: TextAlign.center)),
                    Expanded(child: Text(item.unitPrice.toStringAsFixed(2), textAlign: TextAlign.end)),
                    Expanded(child: Text(item.lineTotal.toStringAsFixed(2), textAlign: TextAlign.end, style: AppTypography.bodyStrong)),
                  ],
                ),
              ),
            const Divider(),
            _row(l10n.fieldSubtotal, order.subtotal.toStringAsFixed(2)),
            _row(l10n.fieldDiscount, order.discountTotal.toStringAsFixed(2)),
            _row(l10n.fieldTax, order.taxTotal.toStringAsFixed(2)),
            _row(l10n.fieldGrandTotal, order.grandTotal.toStringAsFixed(2), strong: true),
            _row(l10n.fieldPaidAmount, order.paidAmount.toStringAsFixed(2)),
            _row(l10n.fieldRemainingAmount, order.remainingAmount.toStringAsFixed(2)),
          ],
        ),
      ),
      AppCard(
        title: Text(l10n.details),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            _row(l10n.fieldCustomer, order.customerName ?? '—'),
            _row(l10n.fieldCreatedBy, order.createdBy),
            _row(l10n.fieldDate, order.createdAt.toString().split('.').first),
            _row(l10n.fieldPaymentMethod, _paymentMethodLabel(l10n, order.paymentMethod)),
            Row(
              children: [
                Expanded(child: Text(l10n.fieldPaymentStatus, style: AppTypography.label)),
                StatusBadge(
                  label: switch (order.paymentStatus) {
                    PaymentStatus.paid => l10n.statusPaid,
                    PaymentStatus.partiallyPaid => l10n.statusPartiallyPaid,
                    PaymentStatus.unpaid => l10n.statusUnpaid,
                  },
                  tone: switch (order.paymentStatus) {
                    PaymentStatus.paid => StatusTone.success,
                    PaymentStatus.partiallyPaid => StatusTone.warning,
                    PaymentStatus.unpaid => StatusTone.danger,
                  },
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label)),
                StatusBadge(label: orderStatusLabel(l10n, order.status), tone: orderStatusTone(order.status)),
              ],
            ),
            if (order.notes != null) ...[const Divider(), Text(order.notes!)],
          ],
        ),
      ),
      AppCard(
        title: Text(l10n.fieldOrderHistory),
        child: AppEmptyState(
          icon: Icons.history,
          title: l10n.emptyStateDefaultTitle,
          description: dataSourceNotice(l10n),
        ),
      ),
    ];
  }

  Widget _row(String label, String value, {bool strong = false}) {
    final style = strong ? AppTypography.sectionTitle : AppTypography.body;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: strong ? style : AppTypography.label),
        // Flexible + ellipsis: a long value (e.g. a customer's full name)
        // in this narrow sidebar column otherwise overflows instead of
        // shrinking — same class of bug as AppButton's label, fixed the
        // same way.
        Flexible(child: Text(value, style: style, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
      ],
    );
  }

  String _paymentMethodLabel(AppLocalizations l10n, PaymentMethod method) => switch (method) {
        PaymentMethod.cash => l10n.paymentMethodCash,
        PaymentMethod.bankTransfer => l10n.paymentMethodBankTransfer,
        PaymentMethod.card => l10n.paymentMethodCard,
        PaymentMethod.other => l10n.paymentMethodOther,
      };
}
