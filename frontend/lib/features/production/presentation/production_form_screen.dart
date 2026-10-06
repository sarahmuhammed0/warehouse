import '../../../core/config/data_source_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../../employees/data/employee_providers.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../data/production_models.dart';
import '../data/production_providers.dart';

/// Create production order (§21) — picking a finished product auto-loads
/// its Bill of Materials template; quantities scale with the planned batch
/// size so the requirement list always matches what's actually being made.
class ProductionFormScreen extends ConsumerStatefulWidget {
  const ProductionFormScreen({super.key});

  @override
  ConsumerState<ProductionFormScreen> createState() => _ProductionFormScreenState();
}

class _ProductionFormScreenState extends ConsumerState<ProductionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Product? _product;
  String? _assignedUserId;
  String? _assignedUserName;
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(List<BomLine> bom) async {
    final l10n = AppLocalizations.of(context)!;

    // The form answers for its own fields now. This used to be
    // `if (_product == null) _error = l10n.requiredFieldMessage` — a bare
    // "This field is required." printed above the buttons, naming no field,
    // while the Product picker it meant sat unmarked and un-reddened further up
    // the page. With the picker `required: true` inside a real `Form`, the
    // message lands on the field that is missing, which is the point of saying
    // it at all.
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    // Safe to parse: the quantity field is validated above as a whole number
    // greater than zero. It used to fall back to `?? 1`, so an unreadable box
    // quietly became a batch of one.
    final qty = int.parse(_quantity.text.trim());
    try {
      await ref.read(productionRepositoryProvider).create(
            ProductionDraft(
              productId: _product!.id,
              productName: _product!.name,
              quantityPlanned: qty,
              materials: [for (final m in bom) BomLine(materialProductId: m.materialProductId, materialProductName: m.materialProductName, quantityRequired: m.quantityRequired * qty, unit: m.unit)],
              assignedUserId: _assignedUserId,
              assignedUserName: _assignedUserName,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      await ref.read(productionListControllerProvider.notifier).reload();
      if (mounted) context.go(AppRoutes.production);
    } on Failure catch (error) {
      // The server's own words. `catch (_) => unableToSave` turned a specific
      // "Must be greater than zero." into "Unable to save", which tells the
      // operator nothing about what to change.
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final productsAsync = ref.watch(productPickerOptionsProvider);
    final employeesAsync = ref.watch(employeePickerOptionsProvider);
    final bomAsync = _product == null ? const AsyncValue<List<BomLine>>.data([]) : ref.watch(bomForProductProvider(_product!.id));

    return PageScaffold(
      title: '${l10n.add} ${l10n.navProduction}',
      showBackButton: true,
      backFallbackRoute: AppRoutes.production,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AppCard(
              title: Text(l10n.fieldProduct),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  productsAsync.when(
                    data: (products) {
                      final finished = products.where((p) => p.productType == ProductType.finishedGood).toList();

                      // A required picker with nothing in it is not a field
                      // somebody forgot to fill — it is a dead end, and every
                      // business that had not created a finished product yet
                      // landed in it. The form said "This field is required."
                      // and never said that the thing to do was go make a
                      // product first. Same shape as the missing warehouse that
                      // made stock impossible to add.
                      if (finished.isEmpty) {
                        return AppEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: l10n.noFinishedProductsYet,
                          description: dataSourceNotice(l10n),
                          actionLabel: '${l10n.add} ${l10n.navProducts}',
                          onAction: () => context.go(AppRoutes.productNew),
                        );
                      }

                      return AppSearchableSelectField<String>(
                        key: const ValueKey('productionProductPicker'),
                        label: l10n.fieldProduct,
                        hintText: l10n.selectPlaceholder,
                        required: true,
                        options: [for (final p in finished) AppSelectOption(p.id, p.name)],
                        onSelected: (id) => setState(() => _product = products.firstWhere((p) => p.id == id)),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    // Not `SizedBox.shrink()`. Swallowing this removed the one
                    // required field on the page, leaving a form that could
                    // never be satisfied and a message pointing at a field that
                    // was no longer on screen.
                    error: (_, _) => Text(l10n.unableToLoad, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  AppTextField.number(
                    key: const ValueKey('productionQuantity'),
                    label: l10n.fieldQuantity,
                    controller: _quantity,
                    allowDecimal: false,
                    required: true,
                    // The server's `positiveQuantitySchema` refuses zero, so the
                    // field refuses it here rather than letting the save
                    // round-trip to find out.
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      return (parsed == null || parsed <= 0) ? l10n.quantityMustBePositive : null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  employeesAsync.when(
                    // Optional, and it has to actually be an employee: the
                    // server stores `assigned_user_id`. This was a free-text
                    // name box whose contents were never put in the request at
                    // all — typed in, and gone on save.
                    data: (employees) => AppDropdownField<String>(
                      key: const ValueKey('productionEmployee'),
                      label: l10n.fieldEmployee,
                      value: _assignedUserId,
                      options: [for (final e in employees) AppSelectOption(e.id, e.name)],
                      onChanged: (value) => setState(() {
                        _assignedUserId = value;
                        _assignedUserName = value == null ? null : employees.firstWhere((e) => e.id == value).name;
                      }),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            if (_product != null)
              AppCard(
                title: Text('${l10n.navProduction} — Bill of Materials'),
                child: bomAsync.when(
                  data: (bom) {
                    final qty = int.tryParse(_quantity.text.trim()) ?? 1;
                    if (bom.isEmpty) return AppEmptyState(icon: Icons.precision_manufacturing_outlined, title: l10n.emptyStateDefaultTitle, description: dataSourceNotice(l10n));
                    return Column(
                      children: [
                        for (final line in bom)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(line.materialProductName)),
                                Text('${line.quantityRequired * qty} ${line.unit}', style: AppTypography.bodyStrong),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ),
            AppTextField.multiline(label: l10n.fieldNotes, controller: _notes, maxLines: 2),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 12,
              children: [
                AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => context.go(AppRoutes.production)),
                AppButton(key: const ValueKey('productionSave'), label: l10n.create, loading: _saving, onPressed: _saving ? null : () => _submit(bomAsync.asData?.value ?? [])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
