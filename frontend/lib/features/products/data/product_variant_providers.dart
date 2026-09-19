import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'product_variant_models.dart';

final productVariantsProvider = NotifierProvider<ProductVariantsController, Map<String, List<ProductVariant>>>(ProductVariantsController.new);

class ProductVariantsController extends Notifier<Map<String, List<ProductVariant>>> {
  int _nextId = 1;

  @override
  Map<String, List<ProductVariant>> build() => {};

  List<ProductVariant> forProduct(String productId) => state[productId] ?? const [];

  void add(String productId, {required String attributeLabel, required String sku, required double price, required double cost, required int quantity}) {
    final variant = ProductVariant(id: 'var-${_nextId++}', productId: productId, attributeLabel: attributeLabel, sku: sku, price: price, cost: cost, quantity: quantity);
    state = {...state, productId: [...forProduct(productId), variant]};
  }

  void remove(String productId, String variantId) {
    state = {...state, productId: forProduct(productId).where((v) => v.id != variantId).toList()};
  }
}
