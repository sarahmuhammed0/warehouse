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
import '../../../theme/app_typography.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../../suppliers/data/supplier_providers.dart';
import '../data/purchase_models.dart';
import '../data/purchase_providers.dart';

/// Create purchase (§20). Line items use `unitCost`, not `unitPrice` —
/// purchases are a cost-side document, deliberately structured differently
/// from `OrderFormScreen`'s selling-price cart even though the mechanics
/// look similar, because conflating the two would risk showing a supplier
/// a business's own selling price by copy-paste error later.
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _CostLine {
  _CostLine({required this.product}) : unitCost = product.purchaseCost ?? 0;
  final Product product;
  int quantity = 1;
  double unitCost;
  double get lineTotal => quantity * unitCost;
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_CostLine> _lines = [];
  String? _supplierId;
  String? _supplierName;
  final _paidAmount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _paymentMethod = 'Cash';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _paidAmount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (sum, l) => sum + l.lineTotal);

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    // Two unrelated problems used to share one nameless message: a supplier that
    // was not chosen, and a purchase with no lines in it. "This field is
    // required." named neither, and the supplier picker it half-meant was
    // neither marked nor reddened, because the screen had no `Form` at all.
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    // Same shape as the Production form: with no suppliers at all the picker is
    // replaced by the empty state, so there is no field for `validate()` to fail
    // on and `_supplierId!` below would throw a null check into the generic
    // catch, answering "Unable to save" under a panel that already says what is
    // actually wrong.
    if (_supplierId == null) {
      setState(() => _error = l10n.noSuppliersYet);
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = l10n.addAtLeastOneItem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(purchaseRepositoryProvider).create(
            PurchaseDraft(
              supplierId: _supplierId!,
              supplierName: _supplierName!,
              items: [for (final l in _lines) PurchaseItemDraft(productId: l.product.id, productName: l.product.name, quantity: l.quantity, unitCost: l.unitCost)],
              paidAmount: double.tryParse(_paidAmount.text.trim()) ?? 0,
              paymentMethod: _paymentMethod,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      await ref.read(purchaseListControllerProvider.notifier).reload();
      if (mounted) context.go(AppRoutes.purchases);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final suppliersAsync = ref.watch(supplierPickerOptionsProvider);
    final productsAsync = ref.watch(productPickerOptionsProvider);

    return PageScaffold(
      title: '${l10n.add} ${l10n.navPurchases}',
      showBackButton: true,
      backFallbackRoute: AppRoutes.purchases,
      body: Form(
        key: _formKey,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          AppCard(
            title: Text(l10n.fieldSupplier),
            child: suppliersAsync.when(
              data: (suppliers) {
                // An empty required picker is a dead end, not a field somebody
                // forgot. A business with no suppliers yet could never get past
                // this screen, and the form said "This field is required."
                // rather than naming the thing to go and do.
                if (suppliers.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: l10n.noSuppliersYet,
                    actionLabel: '${l10n.add} ${l10n.navSuppliers}',
                    onAction: () => context.go(AppRoutes.suppliers),
                  );
                }
                return AppSearchableSelectField<String>(
                  key: const ValueKey('purchaseSupplierPicker'),
                  label: l10n.fieldSupplier,
                  hintText: l10n.selectPlaceholder,
                  required: true,
                  options: [for (final s in suppliers) AppSelectOption(s.id, s.name)],
                  onSelected: (id) {
                    final match = suppliers.firstWhere((s) => s.id == id);
                    setState(() {
                      _supplierId = id;
                      _supplierName = match.name;
                    });
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              // Not `SizedBox.shrink()` — swallowing this removed the required
              // field from the page and left a form nothing could satisfy.
              error: (_, _) => Text(l10n.unableToLoad, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                    options: [for (final p in products) AppSelectOption(p.id, p.name)],
                    onSelected: (id) => setState(() => _lines.add(_CostLine(product: products.firstWhere((p) => p.id == id)))),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                if (_lines.isEmpty)
                  AppEmptyState(icon: Icons.shopping_cart_outlined, title: l10n.emptyStateDefaultTitle)
                else
                  for (final line in _lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(line.product.name)),
                          SizedBox(
                            width: 70,
                            child: TextFormField(
                              initialValue: '${line.quantity}',
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: l10n.fieldQuantity),
                              onChanged: (v) => setState(() => line.quantity = int.tryParse(v) ?? line.quantity),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 90,
                            child: TextFormField(
                              initialValue: line.unitCost.toStringAsFixed(2),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: l10n.fieldPurchaseCost),
                              onChanged: (v) => setState(() => line.unitCost = double.tryParse(v) ?? line.unitCost),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _lines.remove(line))),
                        ],
                      ),
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
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l10n.fieldGrandTotal, style: AppTypography.sectionTitle), Text(_total.toStringAsFixed(2), style: AppTypography.sectionTitle)]),
                AppDropdownField<String>(
                  label: l10n.fieldPaymentMethod,
                  value: _paymentMethod,
                  options: [
                    AppSelectOption(l10n.paymentMethodCash, l10n.paymentMethodCash),
                    AppSelectOption(l10n.paymentMethodBankTransfer, l10n.paymentMethodBankTransfer),
                    AppSelectOption(l10n.paymentMethodCard, l10n.paymentMethodCard),
                    AppSelectOption(l10n.paymentMethodOther, l10n.paymentMethodOther),
                  ],
                  onChanged: (v) => setState(() => _paymentMethod = v ?? l10n.paymentMethodCash),
                ),
                AppTextField.number(label: l10n.fieldPaidAmount, controller: _paidAmount, onChanged: (_) => setState(() {})),
                AppTextField.multiline(label: l10n.fieldNotes, controller: _notes, maxLines: 2),
                Text(
                  '${l10n.statusCompleted}: ${l10n.navInventory} +',
                  style: AppTypography.helperText,
                ),
              ],
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 12,
            children: [
              AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => context.go(AppRoutes.purchases)),
              AppButton(key: const ValueKey('purchaseSave'), label: l10n.create, loading: _saving, onPressed: _saving ? null : _submit),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
