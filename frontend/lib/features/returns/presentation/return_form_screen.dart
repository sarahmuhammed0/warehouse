import 'package:flutter/material.dart';
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
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../data/return_models.dart';
import '../data/return_providers.dart';

/// Create return (§16) — whole order, selected products, or partial
/// quantity: the per-line quantity stepper (capped at the order's own line
/// quantity) covers all three without three different screens.
class ReturnFormScreen extends ConsumerStatefulWidget {
  const ReturnFormScreen({super.key, this.orderId});

  /// Preselects the order to return against.
  ///
  /// The Orders detail screen offers Return on a completed order. It used
  /// to just flip the status to Returned, which left the Returns module
  /// empty -- the order claimed to have been returned and no return record
  /// existed. It now sends the user here with the order already chosen, so
  /// the return is really created and goes through Requested -> Approved ->
  /// Completed like any other (and restocks on completion).
  final String? orderId;

  @override
  ConsumerState<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends ConsumerState<ReturnFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Order? _order;
  final Map<String, int> _returnQuantities = {};
  final Map<String, ItemCondition> _conditions = {};
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _refundAmount {
    if (_order == null) return 0;
    var total = 0.0;
    for (final item in _order!.items) {
      final qty = _returnQuantities[item.productId] ?? 0;
      if (qty > 0) total += qty * item.unitPrice;
    }
    return total;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final items = <ReturnItemDraft>[
      for (final item in _order?.items ?? <OrderLineItem>[])
        if ((_returnQuantities[item.productId] ?? 0) > 0)
          ReturnItemDraft(
            productId: item.productId,
            productName: item.productName,
            quantity: _returnQuantities[item.productId]!,
            condition: _conditions[item.productId] ?? ItemCondition.sellable,
          ),
    ];
    // Three different problems used to share one nameless message — no order
    // picked, no quantity entered, no reason given — printed as "This field is
    // required." above the buttons while none of the three fields it could have
    // meant was marked or reddened. The order picker and the reason answer for
    // themselves now; only the quantities are not a field, so only they still
    // need a line of their own.
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (items.isEmpty) {
      setState(() => _error = l10n.addAtLeastOneItem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(returnRepositoryProvider).create(
            ReturnDraft(
              orderId: _order!.id,
              orderNumber: _order!.orderNumber,
              customerName: _order!.customerName,
              items: items,
              reason: _reason.text.trim(),
              refundAmount: _refundAmount,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      await ref.read(returnListControllerProvider.notifier).reload();
      if (mounted) context.go(AppRoutes.returns);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ordersAsync = ref.watch(completedOrdersProvider);
    // Resolve the preselected order once its list has loaded.
    final preselect = widget.orderId;
    if (preselect != null && _order == null) {
      final match = ordersAsync.asData?.value.where((o) => o.id == preselect);
      if (match != null && match.isNotEmpty) {
        _order = match.first;
      }
    }

    return PageScaffold(
      title: '${l10n.add} ${l10n.navReturns}',
      showBackButton: true,
      backFallbackRoute: AppRoutes.returns,
      body: Form(
        key: _formKey,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppCard(
            title: Text(l10n.fieldOrderNumber),
            child: ordersAsync.when(
              data: (orders) => AppSearchableSelectField<String>(
                key: const ValueKey('returnOrderPicker'),
                label: l10n.fieldOrderNumber,
                hintText: l10n.selectPlaceholder,
                required: true,
                options: [for (final o in orders) AppSelectOption(o.id, '${o.orderNumber} — ${o.customerName ?? l10n.noneOption}')],
                onSelected: (id) => setState(() {
                  _order = orders.firstWhere((o) => o.id == id);
                  _returnQuantities.clear();
                  _conditions.clear();
                }),
              ),
              loading: () => const LinearProgressIndicator(),
              // Not `SizedBox.shrink()` — swallowing this removed the required
              // field from the page and left a form nothing could satisfy.
              error: (_, _) => Text(l10n.unableToLoad, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
          if (_order == null)
            AppEmptyState(icon: Icons.assignment_return_outlined, title: l10n.emptyStateDefaultTitle)
          else
            AppCard(
              title: Text(l10n.fieldProduct),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  for (final item in _order!.items)
                    Row(
                      children: [
                        Expanded(flex: 2, child: Text(item.productName)),
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            initialValue: '0',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: l10n.fieldQuantity, helperText: 'max ${item.quantity}'),
                            onChanged: (v) => setState(() => _returnQuantities[item.productId] = (int.tryParse(v) ?? 0).clamp(0, item.quantity)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: AppDropdownField<ItemCondition>(
                            label: l10n.fieldStatus,
                            value: _conditions[item.productId] ?? ItemCondition.sellable,
                            options: [
                              AppSelectOption(ItemCondition.sellable, l10n.statusActive),
                              AppSelectOption(ItemCondition.damaged, l10n.statusRejected),
                            ],
                            onChanged: (v) => setState(() => _conditions[item.productId] = v ?? ItemCondition.sellable),
                          ),
                        ),
                      ],
                    ),
                  AppTextField(label: l10n.fieldReason, controller: _reason, required: true),
                  AppTextField.multiline(label: l10n.fieldNotes, controller: _notes, maxLines: 2),
                  Text('${l10n.fieldRemainingAmount} (${l10n.returnAction}): ${_refundAmount.toStringAsFixed(2)}'),
                ],
              ),
            ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 12,
            children: [
              AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => context.go(AppRoutes.returns)),
              AppButton(key: const ValueKey('returnSave'), label: l10n.create, loading: _saving, onPressed: _saving ? null : _submit),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
