/// Products (spec §8) — the frontend's richest single entity. Every field
/// the spec lists exists here, but almost all of them are nullable: "the
/// product form must adapt based on the configured business type/custom
/// fields... do not force unnecessary fields" (§8's explicit instruction).
/// The form (`product_form_screen.dart`) is what actually adapts what it
/// shows; the model itself simply has room for every field so no future
/// business type is blocked by a missing column.
enum ProductType { finishedGood, rawMaterial, component }

enum ProductStatus { active, inactive, discontinued }

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.code,
    this.sku,
    this.barcode,
    required this.categoryId,
    required this.categoryName,
    this.brand,
    this.imageUrl,
    this.description,
    this.shortDescription,
    required this.status,
    required this.productType,
    // Inventory
    required this.currentQuantity,
    this.minStock,
    this.maxStock,
    this.reorderLevel,
    this.reservedQuantity = 0,
    this.warehouseName,
    this.shelfRackBin,
    required this.unit,
    // Financial
    this.purchaseCost,
    this.sellingPrice,
    this.wholesalePrice,
    this.discountPrice,
    this.taxRate,
    // Optional
    this.size,
    this.length,
    this.width,
    this.height,
    this.weight,
    this.color,
    this.material,
    this.model,
    this.manufacturer,
    this.serialNumber,
    this.batchNumber,
    this.expiryDate,
    this.warrantyPeriod,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final String? sku;
  final String? barcode;
  final String categoryId;
  final String categoryName;
  final String? brand;
  final String? imageUrl;
  final String? description;
  final String? shortDescription;
  final ProductStatus status;
  final ProductType productType;

  final int currentQuantity;
  final int? minStock;
  final int? maxStock;
  final int? reorderLevel;
  final int reservedQuantity;
  final String? warehouseName;
  final String? shelfRackBin;
  final String unit;

  final double? purchaseCost;
  final double? sellingPrice;
  final double? wholesalePrice;
  final double? discountPrice;
  final double? taxRate;

  final String? size;
  final double? length;
  final double? width;
  final double? height;
  final double? weight;
  final String? color;
  final String? material;
  final String? model;
  final String? manufacturer;
  final String? serialNumber;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? warrantyPeriod;

  final DateTime createdAt;
  final DateTime updatedAt;

  int get availableQuantity => currentQuantity - reservedQuantity;

  bool get isLowStock => reorderLevel != null && currentQuantity > 0 && currentQuantity <= reorderLevel!;
  bool get isOutOfStock => currentQuantity <= 0;
  bool get isOverstock => maxStock != null && currentQuantity > maxStock!;

  double? get marginPercent {
    if (purchaseCost == null || sellingPrice == null || purchaseCost == 0) return null;
    return ((sellingPrice! - purchaseCost!) / purchaseCost!) * 100;
  }
}

/// The editable shape for create/edit — mirrors [Product] minus
/// server/repository-assigned fields (id, timestamps, reservedQuantity,
/// categoryName which is derived from categoryId).
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.code,
    this.sku,
    this.barcode,
    required this.categoryId,
    this.brand,
    this.imageUrl,
    this.description,
    this.shortDescription,
    this.status = ProductStatus.active,
    this.productType = ProductType.finishedGood,
    required this.currentQuantity,
    this.minStock,
    this.maxStock,
    this.reorderLevel,
    this.warehouseName,
    this.shelfRackBin,
    required this.unit,
    this.purchaseCost,
    this.sellingPrice,
    this.wholesalePrice,
    this.discountPrice,
    this.taxRate,
    this.size,
    this.length,
    this.width,
    this.height,
    this.weight,
    this.color,
    this.material,
    this.model,
    this.manufacturer,
    this.serialNumber,
    this.batchNumber,
    this.expiryDate,
    this.warrantyPeriod,
  });

  final String name;
  final String code;
  final String? sku;
  final String? barcode;
  final String categoryId;
  final String? brand;
  final String? imageUrl;
  final String? description;
  final String? shortDescription;
  final ProductStatus status;
  final ProductType productType;
  final int currentQuantity;
  final int? minStock;
  final int? maxStock;
  final int? reorderLevel;
  final String? warehouseName;
  final String? shelfRackBin;
  final String unit;
  final double? purchaseCost;
  final double? sellingPrice;
  final double? wholesalePrice;
  final double? discountPrice;
  final double? taxRate;
  final String? size;
  final double? length;
  final double? width;
  final double? height;
  final double? weight;
  final String? color;
  final String? material;
  final String? model;
  final String? manufacturer;
  final String? serialNumber;
  final String? batchNumber;
  final DateTime? expiryDate;
  final String? warrantyPeriod;
}

/// Common units of measurement (§8's examples) — a fixed catalog for now;
/// Settings → Inventory Settings is where a business will eventually be
/// able to add its own (§32 of the frontend brief).
const List<String> commonUnits = [
  'Piece',
  'Box',
  'Set',
  'Meter',
  'Kilogram',
  'Liter',
  'Square meter',
  'Cubic meter',
];
