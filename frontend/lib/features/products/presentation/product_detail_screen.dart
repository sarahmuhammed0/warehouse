import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../shared/layout/responsive/responsive_layout.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../data/product_models.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/presentation/stock_adjustment_dialog.dart';
import '../data/product_providers.dart';
import 'product_history_screen.dart';
import '../data/product_variant_models.dart';
import '../data/product_variant_providers.dart';

/// Product detail (§8: "view/edit/stock/history/archive"). The history/
/// movement feed here reuses Inventory's own movement model — see
/// `features/inventory/presentation/inventory_screen.dart`'s movement list
/// for the same shape, filtered to this one product.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(productByIdProvider(productId));

    return async.when(
      loading: () => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.products,
        body: const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      ),
      error: (_, _) => PageScaffold(
        title: l10n.details,
        showBackButton: true,
        backFallbackRoute: AppRoutes.products,
        body: AppErrorState(
          message: l10n.unableToLoad,
          onRetry: () => ref.invalidate(productByIdProvider(productId)),
        ),
      ),
      data: (product) => PageScaffold(
        title: product.name,
        showBackButton: true,
        backFallbackRoute: AppRoutes.products,
        primaryAction: AppButton(
          label: l10n.edit,
          icon: Icons.edit_outlined,
          onPressed: () => context.push(AppRoutes.productEdit(product.id)),
        ),
        secondaryActions: [
          // The whole Inventory card below was read-only text: you could
          // see a product was out of stock and had no way to act on it
          // without going back to the list.
          AppButton(
            key: const ValueKey('productAdjustStock'),
            label: l10n.adjust,
            icon: Icons.tune,
            variant: AppButtonVariant.outline,
            onPressed: () => showStockAdjustmentDialog(context, product),
          ),
          AppButton(
            label: l10n.reportStockMovement,
            icon: Icons.history,
            variant: AppButtonVariant.outline,
            onPressed: () => context.push(AppRoutes.productHistory(product.id)),
          ),
          if (product.barcode != null)
            AppButton(
              label: l10n.print,
              icon: Icons.qr_code_2_outlined,
              variant: AppButtonVariant.outline,
              onPressed: () => _showBarcodeLabelPreview(context, l10n, product),
            ),
        ],
        body: ResponsiveLayout(
          mobile: (context) => Column(spacing: 16, children: _sections(context, l10n, product)),
          desktop: (context) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              Expanded(flex: 2, child: Column(spacing: 16, children: _sections(context, l10n, product).sublist(0, 2))),
              Expanded(child: Column(spacing: 16, children: _sections(context, l10n, product).sublist(2))),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, AppLocalizations l10n, Product product) {
    final colors = context.colors;
    return [
      AppCard(
        title: Text(l10n.details),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            _row(l10n.fieldCode, product.code),
            _row(l10n.fieldSku, product.sku ?? '—'),
            _row(l10n.fieldBarcode, product.barcode ?? '—'),
            _row(l10n.fieldCategory, product.categoryName),
            _row(l10n.fieldBrand, product.brand ?? '—'),
            Row(
              children: [
                Expanded(child: Text(l10n.fieldStatus, style: AppTypography.label.copyWith(color: colors.textMuted))),
                StatusBadge(
                  label: switch (product.status) {
                    ProductStatus.active => l10n.statusActive,
                    ProductStatus.inactive => l10n.statusInactive,
                    ProductStatus.discontinued => l10n.statusCancelled,
                  },
                  tone: switch (product.status) {
                    ProductStatus.active => StatusTone.success,
                    ProductStatus.inactive => StatusTone.neutral,
                    ProductStatus.discontinued => StatusTone.danger,
                  },
                ),
              ],
            ),
            if (product.description != null) ...[
              const Divider(),
              Text(product.description!, style: AppTypography.body.copyWith(color: colors.textSecondary)),
            ],
          ],
        ),
      ),
      AppCard(
        title: Text(l10n.fieldPurchaseCost),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            _row(l10n.fieldPurchaseCost, product.purchaseCost?.toStringAsFixed(2) ?? '—'),
            _row(l10n.fieldSellingPrice, product.sellingPrice?.toStringAsFixed(2) ?? '—'),
            _row(l10n.fieldWholesalePrice, product.wholesalePrice?.toStringAsFixed(2) ?? '—'),
            _row(l10n.fieldMargin, product.marginPercent != null ? '${product.marginPercent!.toStringAsFixed(1)}%' : '—'),
          ],
        ),
      ),
      AppCard(
        title: Text(l10n.navInventory),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            _row(l10n.fieldCurrentQuantity, '${product.currentQuantity} ${product.unit}'),
            _row(l10n.fieldReservedQuantity, '${product.reservedQuantity}'),
            _row(l10n.fieldAvailableQuantity, '${product.availableQuantity}'),
            _row(l10n.fieldReorderLevel, product.reorderLevel?.toString() ?? '—'),
            _row(l10n.fieldWarehouse, product.warehouseName ?? '—'),
            _row(l10n.fieldShelfRackBin, product.shelfRackBin ?? '—'),
            if (product.isOutOfStock)
              StatusBadge(label: l10n.statusOutOfStock, tone: StatusTone.danger)
            else if (product.isLowStock)
              StatusBadge(label: l10n.statusLowStock, tone: StatusTone.warning),
          ],
        ),
      ),
      // Was a hard-coded empty state. Now the product's five most recent
      // stock movements — real ones, since sales/purchases/returns/
      // production all write them.
      _RecentMovementsCard(productId: product.id, l10n: l10n),
      _VariantsCard(product: product, l10n: l10n),
    ];
  }

  Widget _row(String label, String value) {
    return Builder(
      builder: (context) {
        final colors = context.colors;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: AppTypography.label.copyWith(color: colors.textMuted))),
            Expanded(child: Text(value, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary))),
          ],
        );
      },
    );
  }

  /// Barcode support (spec §31) — label preview only; actual device
  /// scanning and thermal-printer output are out of a Flutter-only phase's
  /// reach (§31: "may use a frontend abstraction/mock scanner"), so this
  /// shows exactly what a printed label would contain.
  void _showBarcodeLabelPreview(BuildContext context, AppLocalizations l10n, Product product) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        // Scrollable, so a form taller than the window scrolls instead of
        // overflowing. Without it a short viewport renders the striped
        // overflow banner and clips whatever did not fit.
        scrollable: true,
        title: Text(l10n.fieldBarcode),
        content: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 60, color: Colors.black, alignment: Alignment.center, child: Text('| ‖ | ‖ || | ‖ |', style: TextStyle(color: Colors.white, letterSpacing: 2))),
              const SizedBox(height: 8),
              Text(product.barcode ?? '', style: AppTypography.bodyStrong),
              Text(product.name, style: AppTypography.caption),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.close))],
      ),
    );
  }
}

/// Product variants (spec §9) — Black/White/Brown-style colorways of one
/// product. In-memory (`productVariantsProvider`), not yet wired to a real
/// `product_variants` table — see `docs/frontend-coverage.md`.
class _VariantsCard extends ConsumerWidget {
  const _VariantsCard({required this.product, required this.l10n});
  final Product product;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Backend mode fetches this product's variants the first time the card is
    // built; a no-op afterwards, and in demo mode.
    ref.read(productVariantsProvider.notifier).ensureLoaded(product.id);
    final variants = ref.watch(productVariantsProvider.select((all) => all[product.id] ?? const <ProductVariant>[]));
    return AppCard(
      title: Text(l10n.fieldModule),
      actions: [IconButton(icon: const Icon(Icons.add, size: 20), tooltip: l10n.add, onPressed: () => _openAddVariantDialog(context, ref))],
      child: variants.isEmpty
          ? AppEmptyState(icon: Icons.style_outlined, title: l10n.emptyStateDefaultTitle)
          : Column(
              children: [
                for (final v in variants)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.attributeLabel),
                    subtitle: Text('${v.sku} · ${v.price.toStringAsFixed(2)} · ${v.quantity} ${product.unit}'),
                    trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => ref.read(productVariantsProvider.notifier).remove(product.id, v.id)),
                  ),
              ],
            ),
    );
  }

  Future<void> _openAddVariantDialog(BuildContext context, WidgetRef ref) async {
    final attribute = TextEditingController();
    final sku = TextEditingController();
    final price = TextEditingController();
    final cost = TextEditingController();
    final quantity = TextEditingController(text: '0');
    await showAppDialog<void>(
      context,
      builder: (context) => AlertDialog(
        // Scrollable, so a form taller than the window scrolls instead of
        // overflowing. Without it a short viewport renders the striped
        // overflow banner and clips whatever did not fit.
        scrollable: true,
        title: Text('${l10n.add} — ${l10n.fieldModule}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(label: 'Color / Size', controller: attribute),
              AppTextField(label: l10n.fieldSku, controller: sku),
              AppTextField.number(label: l10n.fieldSellingPrice, controller: price),
              AppTextField.number(label: l10n.fieldPurchaseCost, controller: cost),
              AppTextField.number(label: l10n.fieldQuantity, controller: quantity, allowDecimal: false),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              if (attribute.text.trim().isEmpty) return;
              ref.read(productVariantsProvider.notifier).add(
                    product.id,
                    attributeLabel: attribute.text.trim(),
                    sku: sku.text.trim(),
                    price: double.tryParse(price.text.trim()) ?? 0,
                    cost: double.tryParse(cost.text.trim()) ?? 0,
                    quantity: int.tryParse(quantity.text.trim()) ?? 0,
                  );
              Navigator.of(context).pop();
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
}

/// The product's recent stock movements, in place of what used to be a
/// permanently empty "Order history" card.
class _RecentMovementsCard extends ConsumerWidget {
  const _RecentMovementsCard({required this.productId, required this.l10n});

  final String productId;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(productMovementsProvider(productId)).asData?.value ?? const <StockMovement>[];

    return AppCard(
      title: Text(l10n.reportStockMovement),
      actions: [
        TextButton(
          onPressed: () => context.push(AppRoutes.productHistory(productId)),
          child: Text(l10n.view),
        ),
      ],
      child: movements.isEmpty
          ? AppEmptyState(icon: Icons.history, title: l10n.emptyStateDefaultTitle, description: l10n.emptyStateDefaultDescription)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in movements.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(m.type.name, style: AppTypography.body)),
                        Text('${m.previousQuantity} → ${m.newQuantity}', style: AppTypography.bodyStrong),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
