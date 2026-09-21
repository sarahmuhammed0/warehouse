import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../../customers/data/customer_providers.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/stock_engine.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../data/order_models.dart';
import '../data/order_providers.dart';
import '../data/order_stock.dart';

/// Sales *and* Orders both create through this one screen (§13/§14) — a
/// cart-style line-item editor with live totals, the "select customer,
/// product, qty, price, discount, tax" + "auto-calc subtotal → grand total →
/// paid/remaining" requirements verbatim. [orderType] decides which module
/// invoked it and therefore what status the created order starts in (see
/// `LocalOrderRepository.create`).
class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key, required this.orderType});
  final OrderType orderType;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _CartLine {
  _CartLine({required this.product});
  final Product product;
  int quantity = 1;
  double discount = 0;

  double get unitPrice => product.sellingPrice ?? 0;

  /// A getter, not a field captured in the constructor.
  ///
  /// It used to be computed once at construction — when `quantity` was
  /// still its default of 1 — and never recomputed. Changing the quantity
  /// updated the subtotal and grand total but left the tax frozen at the
  /// one-unit amount, so a ten-unit line was taxed as one, both on screen
  /// and in the `OrderItemDraft` that got saved.
  double get tax => unitPrice * (product.taxRate ?? 0) / 100 * quantity;

  double get lineTotal => (quantity * unitPrice) - discount + tax;
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final List<_CartLine> _lines = [];
  String? _customerId;
  String? _customerName;
  final _extraCharges = TextEditingController(text: '0');
  final _paidAmount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _extraCharges.dispose();
    _paidAmount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold(0, (sum, l) => sum + (l.quantity * l.unitPrice));
  double get _discountTotal => _lines.fold(0, (sum, l) => sum + l.discount);
  double get _taxTotal => _lines.fold(0, (sum, l) => sum + l.tax);
  double get _extra => double.tryParse(_extraCharges.text.trim()) ?? 0;
  double get _grandTotal => _subtotal - _discountTotal + _taxTotal + _extra;

  void _addProduct(Product product) {
    final existing = _lines.indexWhere((l) => l.product.id == product.id);
    setState(() {
      if (existing != -1) {
        _lines[existing].quantity += 1;
      } else {
        _lines.add(_CartLine(product: product));
      }
    });
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.requiredFieldMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = OrderDraft(
        orderType: widget.orderType,
        customerId: _customerId,
        customerName: _customerName,
        items: [
          for (final l in _lines)
            OrderItemDraft(productId: l.product.id, productName: l.product.name, quantity: l.quantity, unitPrice: l.unitPrice, discount: l.discount, tax: l.tax),
        ],
        extraCharges: _extra,
        paidAmount: double.tryParse(_paidAmount.text.trim()) ?? 0,
        paymentMethod: _paymentMethod,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      final created = await ref.read(orderRepositoryProvider).create(draft);
      await ref.read(orderListControllerProvider.notifier).reload();
      // A quick sale is born Completed (order_models.dart), so the goods
      // leave the shelf now. A standard order starts as a Draft and moves
      // stock when it reaches Completed — see `OrderDetailScreen._transition`.
      if (created.orderType == OrderType.quickSale) {
        await ref.read(stockEngineProvider).apply(
              stockChangesFor(created),
              type: MovementType.sale,
              note: created.orderNumber,
            );
      }
      ref.invalidate(dashboardMetricsProvider);
      if (mounted) context.go(widget.orderType == OrderType.quickSale ? AppRoutes.sales : AppRoutes.orders);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isQuickSale = widget.orderType == OrderType.quickSale;
    final productsAsync = ref.watch(productPickerOptionsProvider);
    final customersAsync = ref.watch(customerPickerOptionsProvider);
    final title = isQuickSale ? l10n.navSales : l10n.navOrders;

    return PageScaffold(
      title: '${l10n.add} $title',
      showBackButton: true,
      backFallbackRoute: isQuickSale ? AppRoutes.sales : AppRoutes.orders,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppCard(
            title: Text(l10n.fieldCustomer),
            child: customersAsync.when(
              data: (customers) => AppSearchableSelectField<String>(
                label: l10n.fieldCustomer,
                hintText: l10n.selectPlaceholder,
                options: [for (final c in customers) AppSelectOption(c.id, c.fullName)],
                onSelected: (id) {
                  final match = customers.firstWhere((c) => c.id == id);
                  setState(() {
                    _customerId = id;
                    _customerName = match.fullName;
                  });
                },
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
          AppCard(
            title: Text(l10n.fieldProduct),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                productsAsync.when(
                  data: (products) => AppSearchableSelectField<String>(
                    label: l10n.fieldProduct,
                    hintText: l10n.selectPlaceholder,
                    options: [for (final p in products) AppSelectOption(p.id, '${p.name} (${p.currentQuantity} ${p.unit})')],
                    onSelected: (id) => _addProduct(products.firstWhere((p) => p.id == id)),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                if (_lines.isEmpty)
                  AppEmptyState(icon: Icons.shopping_cart_outlined, title: l10n.emptyStateDefaultTitle)
                else
                  Column(
                    children: [
                      for (final line in _lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(line.product.name, style: AppTypography.body)),
                              SizedBox(
                                width: 70,
                                child: TextFormField(
                                  initialValue: '${line.quantity}',
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(labelText: l10n.fieldQuantity),
                                  onChanged: (value) => setState(() => line.quantity = int.tryParse(value) ?? line.quantity),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(width: 90, child: Text(line.unitPrice.toStringAsFixed(2), textAlign: TextAlign.end)),
                              const SizedBox(width: 8),
                              // Per-line discount (§13/§14 both list it).
                              // `_CartLine.discount` existed and was always
                              // 0 because nothing could edit it, which made
                              // the Discount row in the totals permanently
                              // read 0.00.
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  initialValue: line.discount == 0 ? '' : '${line.discount}',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: l10n.fieldLineDiscount),
                                  onChanged: (value) => setState(() => line.discount = double.tryParse(value) ?? 0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(width: 90, child: Text(line.lineTotal.toStringAsFixed(2), textAlign: TextAlign.end, style: AppTypography.bodyStrong)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _lines.remove(line)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          AppCard(
            title: Text(l10n.fieldGrandTotal),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _totalsRow(l10n.fieldSubtotal, _subtotal),
                _totalsRow(l10n.fieldDiscount, _discountTotal),
                _totalsRow(l10n.fieldTax, _taxTotal),
                // Was labelled "Reference Number" while feeding extraCharges and the
                // grand total — a money input asking for a reference code.
                AppTextField.number(label: l10n.fieldExtraCharges, controller: _extraCharges, onChanged: (_) => setState(() {})),
                const Divider(),
                _totalsRow(l10n.fieldGrandTotal, _grandTotal, strong: true),
                AppDropdownField<PaymentMethod>(
                  label: l10n.fieldPaymentMethod,
                  value: _paymentMethod,
                  options: [
                    AppSelectOption(PaymentMethod.cash, l10n.paymentMethodCash),
                    AppSelectOption(PaymentMethod.bankTransfer, l10n.paymentMethodBankTransfer),
                    AppSelectOption(PaymentMethod.card, l10n.paymentMethodCard),
                    AppSelectOption(PaymentMethod.other, l10n.paymentMethodOther),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value ?? PaymentMethod.cash),
                ),
                AppTextField.number(label: l10n.fieldPaidAmount, controller: _paidAmount, onChanged: (_) => setState(() {})),
                _totalsRow(l10n.fieldRemainingAmount, _grandTotal - (double.tryParse(_paidAmount.text) ?? 0)),
                AppTextField.multiline(label: l10n.fieldNotes, controller: _notes, maxLines: 2),
              ],
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 12,
            children: [
              AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => context.go(isQuickSale ? AppRoutes.sales : AppRoutes.orders)),
              AppButton(label: l10n.create, loading: _saving, onPressed: _saving ? null : _submit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalsRow(String label, double value, {bool strong = false}) {
    final style = strong ? AppTypography.sectionTitle : AppTypography.body;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value.toStringAsFixed(2), style: style)],
    );
  }
}
