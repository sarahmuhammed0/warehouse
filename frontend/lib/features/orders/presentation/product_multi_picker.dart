import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../products/data/product_models.dart';

/// Picks several products at once, over the form rather than away from it.
///
/// The sale form's own picker takes one product per visit: choose, watch it land
/// in the cart, open the list again for the next one. For a sale of a dozen
/// lines that is a dozen round trips through the same dropdown.
///
/// A dialog, deliberately, not a route: leaving the screen to build a cart means
/// leaving a half-written sale behind, and coming back to it is the part people
/// get wrong. Everything typed into the form is still there underneath.
///
/// Returns the chosen products, or null if it was dismissed. An empty selection
/// cannot be confirmed — the Add button stays disabled — so "added nothing"
/// never looks like "added something that vanished".
Future<List<Product>?> showProductMultiPicker(
  BuildContext context, {
  required List<Product> products,
  Set<String> alreadyInCart = const {},
}) {
  return showDialog<List<Product>>(
    context: context,
    builder: (context) => _ProductMultiPicker(products: products, alreadyInCart: alreadyInCart),
  );
}

class _ProductMultiPicker extends StatefulWidget {
  const _ProductMultiPicker({required this.products, required this.alreadyInCart});

  final List<Product> products;

  /// Shown ticked and locked: they are in the sale already, and offering to add
  /// them again would imply a second line rather than a bigger quantity.
  final Set<String> alreadyInCart;

  @override
  State<_ProductMultiPicker> createState() => _ProductMultiPickerState();
}

class _ProductMultiPickerState extends State<_ProductMultiPicker> {
  final _selected = <String>{};
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Product> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.products;
    return widget.products.where((p) {
      return p.name.toLowerCase().contains(query) ||
          (p.sku ?? '').toLowerCase().contains(query) ||
          p.code.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final visible = _visible;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
      title: Text(l10n.addProductsTitle, style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary)),
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      content: SizedBox(
        // Bounded, because the list inside scrolls. A catalogue of a thousand
        // products must not try to grow the dialog past the screen.
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const ValueKey('productPickerSearch'),
              label: l10n.search,
              controller: _search,
              hintText: l10n.searchPlaceholder,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        l10n.emptyStateDefaultTitle,
                        style: AppTypography.body.copyWith(color: colors.textMuted),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        key: const ValueKey('productPickerList'),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final product = visible[index];
                          final already = widget.alreadyInCart.contains(product.id);
                          final ticked = already || _selected.contains(product.id);
                          return CheckboxListTile(
                            key: ValueKey('pick:${product.id}'),
                            value: ticked,
                            // Locked rather than hidden: seeing it ticked
                            // explains why it cannot be chosen again.
                            onChanged: already
                                ? null
                                : (on) => setState(() {
                                    if (on == true) {
                                      _selected.add(product.id);
                                    } else {
                                      _selected.remove(product.id);
                                    }
                                  }),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(product.name, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                            subtitle: Text(
                              '${product.sku ?? product.code} · ${product.currentQuantity} ${product.unit}',
                              style: AppTypography.caption.copyWith(color: colors.textMuted),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      actions: [
        Row(
          children: [
            Text(
              l10n.selectedCount(_selected.length),
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            const Spacer(),
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              key: const ValueKey('productPickerAdd'),
              label: l10n.add,
              // Nothing ticked is nothing to add; a button that closes the
              // dialog and changes nothing reads as a failure.
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                        widget.products.where((p) => _selected.contains(p.id)).toList(),
                      ),
            ),
          ],
        ),
      ],
    );
  }
}
