import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/providers.dart';
import '../../inventory/data/inventory_providers.dart';
import 'api_product_variant_repository.dart';
import 'product_variant_models.dart';

final productVariantsProvider = NotifierProvider<ProductVariantsController, Map<String, List<ProductVariant>>>(ProductVariantsController.new);

class ProductVariantsController extends Notifier<Map<String, List<ProductVariant>>> {
  int _nextId = 1;

  /// Which products have been fetched, so a screen rebuilding does not refetch
  /// on every frame. Separate from `state`, which cannot tell "no variants"
  /// apart from "not looked yet".
  final Set<String> _loaded = {};

  bool get _backend => AppModeConfig.mode == AppMode.backend;

  ApiProductVariantRepository get _api => ApiProductVariantRepository(ref.read(apiClientProvider));

  @override
  Map<String, List<ProductVariant>> build() => {};

  List<ProductVariant> forProduct(String productId) => state[productId] ?? const [];

  /// Fetches this product's variants once, the first time something asks to
  /// show them. Safe to call from a widget's `build` — it returns immediately
  /// after the first call for a given product.
  void ensureLoaded(String productId) {
    if (!_backend || _loaded.contains(productId)) return;
    _loaded.add(productId);
    Future.microtask(() => reload(productId));
  }

  Future<void> reload(String productId) async {
    if (!_backend) return;
    try {
      final variants = await _api.list(productId);
      state = {...state, productId: variants};
    } catch (_) {
      // Leaves whatever is already shown. The card is one section of a product
      // page; a failed fetch should not take the page down with it.
      _loaded.remove(productId);
    }
  }

  Future<void> add(
    String productId, {
    required String attributeLabel,
    required String sku,
    required double price,
    required double cost,
    required int quantity,
  }) async {
    if (!_backend) {
      final variant = ProductVariant(id: 'var-${_nextId++}', productId: productId, attributeLabel: attributeLabel, sku: sku, price: price, cost: cost, quantity: quantity);
      state = {...state, productId: [...forProduct(productId), variant]};
      return;
    }

    // An opening quantity has to land somewhere specific — stock lives in a
    // warehouse, not against a product in the abstract. The business's first
    // warehouse is used, which is the only unambiguous choice available
    // without a picker the dialog does not have; where there is none, the
    // variant is still created and simply starts empty.
    final warehouses = await ref.read(warehousesProvider.future);
    await _api.create(
      productId,
      attributeLabel: attributeLabel,
      sku: sku,
      price: price,
      cost: cost,
      quantity: quantity,
      warehouseId: warehouses.isEmpty ? null : int.tryParse(warehouses.first.id),
    );
    await reload(productId);
  }

  Future<void> remove(String productId, String variantId) async {
    if (!_backend) {
      state = {...state, productId: forProduct(productId).where((v) => v.id != variantId).toList()};
      return;
    }
    await _api.delete(productId, variantId);
    await reload(productId);
  }
}
