import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../data/inventory_models.dart';
import '../data/stock_engine.dart';

/// Manual stock increase/decrease (§10/§12 — "manual +/-" is one of the
/// listed movement types). Every adjustment writes a [StockMovement]
/// record; nothing silently changes a product's quantity without one.
///
/// [product] may be omitted: opened from a product row the product is
/// already known, but the dashboard's "Add stock" quick action has no
/// product yet, so the dialog asks for one rather than sending the user off
/// to a list to find the same button.
Future<void> showStockAdjustmentDialog(BuildContext context, [Product? product]) {
  return showAppDialog<void>(context, builder: (context) => StockAdjustmentDialog(product: product));
}

class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends ConsumerState<StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();
  bool _increase = true;
  bool _saving = false;
  String? _error;
  late String? _productId = widget.product?.id;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(Product product) async {
    if (!_formKey.currentState!.validate()) return;
    final qty = int.tryParse(_quantity.text.trim()) ?? 0;
    if (qty <= 0) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Through the engine, like every other stock change in the app: it
      // pairs the movement row with the quantity update and refreshes every
      // provider that shows a quantity. This used to rebuild a full
      // 20-field ProductDraft by hand and forget to reload the Movements
      // tab, so a new adjustment could silently fail to appear there.
      await ref.read(stockEngineProvider).apply(
        [StockChange(productId: product.id, productName: product.name, delta: _increase ? qty : -qty)],
        type: _increase ? MovementType.manualIncrease : MovementType.manualDecrease,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = ref.watch(productPickerOptionsProvider).asData?.value ?? const <Product>[];
    // Always resolve from the live list so the "current quantity" line is
    // right after a previous adjustment in the same session.
    final selected = _productId == null
        ? null
        : options.where((p) => p.id == _productId).firstOrNull ?? widget.product;

    return AlertDialog(
      title: Text(selected == null ? l10n.actionAddStock : '${l10n.adjust} — ${selected.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              if (widget.product == null)
                AppDropdownField<String>(
                  key: const ValueKey('stockProductPicker'),
                  label: l10n.fieldProduct,
                  value: _productId,
                  options: [for (final p in options) AppSelectOption(p.id, '${p.name} (${p.currentQuantity} ${p.unit})')],
                  onChanged: _saving ? null : (value) => setState(() => _productId = value),
                ),
              if (selected != null) Text('${l10n.fieldCurrentQuantity}: ${selected.currentQuantity} ${selected.unit}'),
              AppDropdownField<bool>(
                // Was labelled "Module" — a copy-paste that made the one
                // control deciding whether stock goes up or down unreadable.
                label: l10n.adjust,
                value: _increase,
                options: [
                  AppSelectOption(true, '+ ${l10n.fieldQuantity}'),
                  AppSelectOption(false, '- ${l10n.fieldQuantity}'),
                ],
                onChanged: _saving ? null : (value) => setState(() => _increase = value ?? true),
              ),
              AppTextField.number(key: const ValueKey('stockQuantity'), label: l10n.fieldQuantity, controller: _quantity, allowDecimal: false, required: true, enabled: !_saving),
              AppTextField(label: l10n.fieldReason, controller: _note, enabled: !_saving),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        AppButton(
          key: const ValueKey('stockAdjustSave'),
          label: l10n.save,
          loading: _saving,
          // Disabled until a product is chosen — the dashboard entry point
          // opens with none, and saving "nothing" would be a silent no-op.
          onPressed: _saving || selected == null ? null : () => _submit(selected),
        ),
      ],
    );
  }
}
