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
import '../data/inventory_providers.dart';

/// Manual stock increase/decrease (§10/§12 — "manual +/-" is one of the
/// listed movement types). Every adjustment writes a [StockMovement]
/// record; nothing silently changes a product's quantity without one.
Future<void> showStockAdjustmentDialog(BuildContext context, Product product) {
  return showAppDialog<void>(context, builder: (context) => StockAdjustmentDialog(product: product));
}

class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({super.key, required this.product});
  final Product product;

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

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final qty = int.tryParse(_quantity.text.trim()) ?? 0;
    if (qty <= 0) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryRepositoryProvider).recordAdjustment(
            productId: widget.product.id,
            productName: widget.product.name,
            currentQuantity: widget.product.currentQuantity,
            delta: _increase ? qty : -qty,
            type: _increase ? MovementType.manualIncrease : MovementType.manualDecrease,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      // Reflect the new quantity on the product itself too (§10: inventory
      // stays authoritative on the product record).
      final repo = ref.read(productRepositoryProvider);
      final current = await repo.getById(widget.product.id);
      await repo.update(
        widget.product.id,
        ProductDraft(
          name: current.name,
          code: current.code,
          sku: current.sku,
          barcode: current.barcode,
          categoryId: current.categoryId,
          brand: current.brand,
          description: current.description,
          shortDescription: current.shortDescription,
          status: current.status,
          productType: current.productType,
          currentQuantity: current.currentQuantity + (_increase ? qty : -qty),
          minStock: current.minStock,
          maxStock: current.maxStock,
          reorderLevel: current.reorderLevel,
          warehouseName: current.warehouseName,
          shelfRackBin: current.shelfRackBin,
          unit: current.unit,
          purchaseCost: current.purchaseCost,
          sellingPrice: current.sellingPrice,
          wholesalePrice: current.wholesalePrice,
          discountPrice: current.discountPrice,
          taxRate: current.taxRate,
        ),
      );
      await ref.read(productListControllerProvider.notifier).reload();
      ref.invalidate(productByIdProvider(widget.product.id));
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
    return AlertDialog(
      title: Text('${l10n.adjust} — ${widget.product.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Text('${l10n.fieldCurrentQuantity}: ${widget.product.currentQuantity} ${widget.product.unit}'),
              AppDropdownField<bool>(
                label: l10n.fieldModule,
                value: _increase,
                options: [
                  AppSelectOption(true, '+ ${l10n.fieldQuantity}'),
                  AppSelectOption(false, '- ${l10n.fieldQuantity}'),
                ],
                onChanged: (value) => setState(() => _increase = value ?? true),
              ),
              AppTextField.number(label: l10n.fieldQuantity, controller: _quantity, allowDecimal: false, required: true),
              AppTextField(label: l10n.fieldReason, controller: _note),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => Navigator.of(context).pop()),
        AppButton(label: l10n.save, loading: _saving, onPressed: _saving ? null : _submit),
      ],
    );
  }
}
