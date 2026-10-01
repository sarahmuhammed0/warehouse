import '../../../core/network/api_client.dart';
import 'product_variant_models.dart';

/// Product variants (§9) against the real backend.
///
/// A variant is its own stock slot, not a label on the product: inventory is
/// keyed on (business, product, variant, warehouse, location). So the quantity
/// shown against a variant is that slot's, and creating one with an opening
/// quantity takes a stock movement rather than a field on the variant row.
class ApiProductVariantRepository {
  ApiProductVariantRepository(this._client);

  final ApiClient _client;

  /// §9 stores attributes as JSON — which attributes matter differs per
  /// business. This module models the whole thing as one free-text label, the
  /// way the screen collects it, so the two are reconciled here: a label goes
  /// out under a single `label` attribute and comes back from it.
  ///
  /// A variant created elsewhere with real attributes (`{"color":"Black"}`)
  /// still reads correctly — its pairs are joined for display rather than
  /// showing as blank.
  static String _label(Map<String, dynamic> json) {
    final attributes = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    final single = attributes['label'];
    if (single != null) return '$single';
    if (attributes.isNotEmpty) {
      return attributes.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    }
    return (json['name'] as String?) ?? '';
  }

  static ProductVariant _fromJson(String productId, Map<String, dynamic> json) => ProductVariant(
    id: '${json['id']}',
    productId: productId,
    attributeLabel: _label(json),
    sku: (json['sku'] as String?) ?? '',
    price: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
    cost: (json['purchaseCost'] as num?)?.toDouble() ?? 0,
    // This module's model counts variants in whole units and its form refuses
    // a decimal, so a fractional slot is rounded for display rather than
    // truncated — showing 2 where the server holds 2.5 is wrong either way,
    // but rounding is the smaller lie and never reads as "less than there is".
    quantity: ((json['quantity'] as num?)?.toDouble() ?? 0).round(),
  );

  Future<List<ProductVariant>> list(String productId) async {
    final result = await _client.getList('/products/$productId/variants');
    return result.data.map((row) => _fromJson(productId, row as Map<String, dynamic>)).toList();
  }

  /// Creates the variant, then — only if an opening quantity was given — files
  /// the stock movement that puts that quantity in it.
  ///
  /// Two calls, because they are two facts: a variant exists, and some of it
  /// is on a shelf. The movement is a real `manual_increase` in the ledger
  /// rather than an invisible opening balance, so the stock can be explained
  /// later by the same history as every other quantity in the system.
  ///
  /// If the movement fails the variant still exists with nothing in it, which
  /// is recoverable and visible. Inventing an opening balance that no movement
  /// accounts for would not be.
  Future<ProductVariant> create(
    String productId, {
    required String attributeLabel,
    required String sku,
    required double price,
    required double cost,
    required int quantity,
    int? warehouseId,
  }) async {
    final created = await _client.postJson('/products/$productId/variants', {
      'name': attributeLabel,
      if (sku.isNotEmpty) 'sku': sku,
      'sellingPrice': price,
      'purchaseCost': cost,
      'attributes': {'label': attributeLabel},
    });

    if (quantity > 0 && warehouseId != null) {
      await _client.postJson('/inventory/adjust', {
        'productId': int.tryParse(productId) ?? productId,
        'variantId': created['id'],
        'warehouseId': warehouseId,
        'quantity': quantity,
        'movementType': 'manual_increase',
        'reason': 'Opening quantity for a new variant',
      });
    }

    // Re-read so the returned variant carries the quantity the movement just
    // created, rather than the zero the create response was written before.
    final all = await list(productId);
    return all.firstWhere(
      (v) => v.id == '${created['id']}',
      orElse: () => _fromJson(productId, created),
    );
  }

  Future<void> delete(String productId, String variantId) async {
    await _client.deleteJson('/products/$productId/variants/$variantId');
  }
}
