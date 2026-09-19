/// Product variants (spec §9) — e.g. a sofa's Black/White/Brown colorways.
/// Kept as a separate small in-memory store keyed by `productId` rather
/// than a field on [Product] itself, since a real backend would model this
/// as its own `product_variants` table (architecture §5) with its own SKU/
/// barcode uniqueness, not a nested list on the product row.
class ProductVariant {
  const ProductVariant({required this.id, required this.productId, required this.attributeLabel, required this.sku, required this.price, required this.cost, required this.quantity});
  final String id;
  final String productId;

  /// e.g. "Color: Black" or "Size: 160cm" — free text rather than a typed
  /// attribute system, since the spec's own examples (color, size) don't
  /// imply a fixed attribute schema across every business type.
  final String attributeLabel;
  final String sku;
  final double price;
  final double cost;
  final int quantity;
}
