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
  Product? _product;
  final _quantity = TextEditingController(text: '1');
  final _assignedTo = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _assignedTo.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(List<BomLine> bom) async {
    final l10n = AppLocalizations.of(context)!;
    if (_product == null) {
      setState(() => _error = l10n.requiredFieldMessage);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final qty = int.tryParse(_quantity.text.trim()) ?? 1;
    try {
      await ref.read(productionRepositoryProvider).create(
            ProductionDraft(
              productId: _product!.id,
              productName: _product!.name,
              quantityPlanned: qty,
              materials: [for (final m in bom) BomLine(materialProductId: m.materialProductId, materialProductName: m.materialProductName, quantityRequired: m.quantityRequired * qty, unit: m.unit)],
              assignedTo: _assignedTo.text.trim().isEmpty ? null : _assignedTo.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      await ref.read(productionListControllerProvider.notifier).reload();
      if (mounted) context.go(AppRoutes.production);
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
    final bomAsync = _product == null ? const AsyncValue<List<BomLine>>.data([]) : ref.watch(bomForProductProvider(_product!.id));

    return PageScaffold(
      title: '${l10n.add} ${l10n.navProduction}',
      showBackButton: true,
      backFallbackRoute: AppRoutes.production,
      body: Column(
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
                  data: (products) => AppSearchableSelectField<String>(
                    label: l10n.fieldProduct,
                    hintText: l10n.selectPlaceholder,
                    options: [for (final p in products.where((p) => p.productType == ProductType.finishedGood)) AppSelectOption(p.id, p.name)],
                    onSelected: (id) => setState(() => _product = products.firstWhere((p) => p.id == id)),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                AppTextField.number(label: l10n.fieldQuantity, controller: _quantity, allowDecimal: false, onChanged: (_) => setState(() {})),
                AppTextField(label: l10n.fieldEmployee, controller: _assignedTo),
              ],
            ),
          ),
          if (_product != null)
            AppCard(
              title: Text('${l10n.navProduction} — Bill of Materials'),
              child: bomAsync.when(
                data: (bom) {
                  final qty = int.tryParse(_quantity.text.trim()) ?? 1;
                  if (bom.isEmpty) return AppEmptyState(icon: Icons.precision_manufacturing_outlined, title: l10n.emptyStateDefaultTitle, description: l10n.demoDataNotice);
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
              AppButton(label: l10n.create, loading: _saving, onPressed: _saving ? null : () => _submit(bomAsync.asData?.value ?? [])),
            ],
          ),
        ],
      ),
    );
  }
}
