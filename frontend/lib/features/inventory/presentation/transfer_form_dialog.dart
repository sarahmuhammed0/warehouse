import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../data/inventory_providers.dart';

/// Create a stock transfer between warehouses (§11).
///
/// `LocalInventoryRepository.createTransfer` was fully implemented —
/// generating a TRF number, inserting the row, defaulting to pending — and
/// had **no caller anywhere in the app**. The Transfers tab was a read-only
/// table of seeded rows with no way to add one.
Future<bool?> showTransferFormDialog(BuildContext context) {
  return showAppDialog<bool>(context, builder: (context) => const TransferFormDialog());
}

class TransferFormDialog extends ConsumerStatefulWidget {
  const TransferFormDialog({super.key});

  @override
  ConsumerState<TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends ConsumerState<TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  String? _productId;
  String? _fromId;
  String? _toId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(String productName) async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
    if (quantity <= 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryRepositoryProvider).createTransfer(
            fromWarehouseId: _fromId!,
            toWarehouseId: _toId!,
            productName: productName,
            // The picker already knows which product this is; the real API
            // moves stock by id, since product names are not unique.
            productId: _productId,
            quantity: quantity,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      await ref.read(transferListControllerProvider.notifier).reload();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final warehouses = ref.watch(warehousesProvider).asData?.value ?? const [];
    final products = ref.watch(productPickerOptionsProvider).asData?.value ?? const <Product>[];
    final product = products.where((p) => p.id == _productId).firstOrNull;

    // A transfer from a warehouse to itself is not a transfer — excluding
    // the chosen source from the destination list is cheaper than letting
    // someone pick it and then explaining why it was rejected.
    final destinations = warehouses.where((w) => w.id != _fromId).toList();

    return AlertDialog(
      // Scrollable, so a form taller than the window scrolls instead of
      // overflowing. Without it a short viewport — a laptop, or a browser
      // pane beside an editor — renders the striped overflow banner across
      // the dialog and clips whatever did not fit, including the buttons.
      scrollable: true,
      title: Text('${l10n.add} ${l10n.transfer}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              AppDropdownField<String>(
                key: const ValueKey('transferProduct'),
                label: l10n.fieldProduct,
                value: _productId,
                options: [for (final p in products) AppSelectOption(p.id, '${p.name} (${p.currentQuantity} ${p.unit})')],
                onChanged: _saving ? null : (value) => setState(() => _productId = value),
              ),
              AppDropdownField<String>(
                key: const ValueKey('transferFrom'),
                label: l10n.fieldWarehouse,
                value: _fromId,
                options: [for (final w in warehouses) AppSelectOption(w.id, w.name)],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                          _fromId = value;
                          if (_toId == value) _toId = null;
                        }),
              ),
              AppDropdownField<String>(
                key: const ValueKey('transferTo'),
                label: l10n.fieldLocation,
                value: _toId,
                options: [for (final w in destinations) AppSelectOption(w.id, w.name)],
                onChanged: _saving ? null : (value) => setState(() => _toId = value),
              ),
              AppTextField.number(
                label: l10n.fieldQuantity,
                controller: _quantity,
                allowDecimal: false,
                required: true,
                enabled: !_saving,
                validator: required(l10n.requiredFieldMessage),
              ),
              AppTextField(label: l10n.fieldNotes, controller: _notes, enabled: !_saving),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        AppButton(
          key: const ValueKey('transferSave'),
          label: l10n.create,
          loading: _saving,
          // Disabled until the transfer is actually describable.
          onPressed: _saving || product == null || _fromId == null || _toId == null ? null : () => _submit(product.name),
        ),
      ],
    );
  }
}
