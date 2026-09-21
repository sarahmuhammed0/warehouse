import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_businesses.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'product_models.dart';

abstract class ProductRepository {
  Future<PaginatedResult<Product>> list(PagedQuery query);
  Future<Product> getById(String id);
  Future<Product> create(ProductDraft draft);
  Future<Product> update(String id, ProductDraft draft);
  Future<void> setStatus(String id, ProductStatus status);

  /// Move one product's stock by [delta] (negative to consume).
  ///
  /// Exists because every other module needs exactly this and nothing else:
  /// a sale, a purchase completing, a return restocking, a production run
  /// consuming materials. The alternative — rebuilding a full 20-field
  /// `ProductDraft` just to change one integer — is what made those side
  /// effects not get written in the first place, and it silently overwrites
  /// any field the caller forgets to copy.
  ///
  /// Never writes a movement row itself: `StockEngine` owns that pairing so
  /// stock cannot move without history (spec §12). Call it, not this.
  Future<Product> adjustQuantity(String id, int delta);

  /// Unpaginated, active products only — for pickers in Sales/Orders/
  /// Purchases/Production line-item editors.
  Future<List<Product>> allForPicker();

  /// Every product owned by one tenant — the System Admin's per-business
  /// drill-down (spec §56/§57) and the aggregates its overview sums are
  /// derived from. Deliberately not exposed to business-side screens,
  /// which are single-tenant in demo mode.
  Future<List<Product>> listForBusiness(String businessId);
}

class LocalProductRepository with DemoRepository implements ProductRepository {
  LocalProductRepository() {
    _seed();
  }

  final List<Product> _items = [];
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    void add({
      required String businessId,
      required String name,
      required String code,
      required String categoryId,
      required String categoryName,
      required int qty,
      int? reorder,
      int? maxStock,
      required String unit,
      double? cost,
      double? price,
      ProductType type = ProductType.finishedGood,
      String? color,
      String? material,
    }) {
      _items.add(
        Product(
          id: 'prod-${_nextId++}',
          businessId: businessId,
          name: name,
          code: code,
          sku: 'SKU-${code.toUpperCase()}',
          barcode: '89${(100000000 + _nextId).toString()}',
          categoryId: categoryId,
          categoryName: categoryName,
          brand: null,
          description: null,
          shortDescription: null,
          status: ProductStatus.active,
          productType: type,
          currentQuantity: qty,
          minStock: reorder != null ? (reorder / 2).round() : null,
          maxStock: maxStock,
          reorderLevel: reorder,
          reservedQuantity: qty > 4 ? 2 : 0,
          warehouseName: 'Main Warehouse',
          shelfRackBin: 'A-${_items.length + 1}',
          unit: unit,
          purchaseCost: cost,
          sellingPrice: price,
          wholesalePrice: price != null ? price * 0.85 : null,
          discountPrice: null,
          taxRate: 5,
          color: color,
          material: material,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // Karwan Furniture Factory — finished furniture plus the raw materials
    // it manufactures from (10 products).
    add(businessId: kDemoBusinessKarwan, name: '3-Seat Sofa — Charcoal', code: 'SOFA-3S-CH', categoryId: 'cat-6', categoryName: 'Sofas', qty: 8, reorder: 3, maxStock: 30, unit: 'Piece', cost: 220, price: 420, color: 'Charcoal', material: 'Fabric');
    add(businessId: kDemoBusinessKarwan, name: '3-Seat Sofa — Beige', code: 'SOFA-3S-BG', categoryId: 'cat-6', categoryName: 'Sofas', qty: 2, reorder: 3, maxStock: 30, unit: 'Piece', cost: 220, price: 420, color: 'Beige', material: 'Fabric');
    add(businessId: kDemoBusinessKarwan, name: 'Coffee Table — Oak', code: 'CTB-OAK', categoryId: 'cat-7', categoryName: 'Coffee Tables', qty: 14, reorder: 5, maxStock: 40, unit: 'Piece', cost: 60, price: 120, material: 'Oak wood');
    add(businessId: kDemoBusinessKarwan, name: 'TV Unit — Walnut 180cm', code: 'TVU-WAL-180', categoryId: 'cat-8', categoryName: 'TV Units', qty: 0, reorder: 4, maxStock: 20, unit: 'Piece', cost: 95, price: 190, material: 'Walnut veneer');
    add(businessId: kDemoBusinessKarwan, name: 'Bookshelf — 5 Tier', code: 'SHELF-5T', categoryId: 'cat-1', categoryName: 'Living Room', qty: 3, reorder: 5, maxStock: 20, unit: 'Piece', cost: 45, price: 95);
    add(businessId: kDemoBusinessKarwan, name: 'Solid Pine Timber (2m)', code: 'RAW-PINE-2M', categoryId: 'cat-4', categoryName: 'Raw Materials', qty: 420, reorder: 100, maxStock: 1000, unit: 'Piece', cost: 8, price: null, type: ProductType.rawMaterial, material: 'Pine');
    add(businessId: kDemoBusinessKarwan, name: 'Upholstery Fabric (roll)', code: 'RAW-FAB-01', categoryId: 'cat-4', categoryName: 'Raw Materials', qty: 35, reorder: 15, maxStock: 200, unit: 'Meter', cost: 6, price: null, type: ProductType.rawMaterial, material: 'Cotton blend');
    add(businessId: kDemoBusinessKarwan, name: 'Wood Screws 4x40mm (box)', code: 'HDW-SCR-440', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 180, reorder: 50, maxStock: 500, unit: 'Box', cost: 3, price: null, type: ProductType.rawMaterial);
    add(businessId: kDemoBusinessKarwan, name: 'Metal Table Legs (set of 4)', code: 'HDW-LEG-01', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 60, reorder: 20, maxStock: 200, unit: 'Set', cost: 12, price: null, type: ProductType.component, material: 'Steel');
    add(businessId: kDemoBusinessKarwan, name: 'MDF Board 18mm (sheet)', code: 'RAW-MDF-18', categoryId: 'cat-4', categoryName: 'Raw Materials', qty: 260, reorder: 40, maxStock: 150, unit: 'Sheet', cost: 14, price: null, type: ProductType.rawMaterial, material: 'MDF');

    // Erbil Central Warehouse (4 products).
    add(businessId: kDemoBusinessErbil, name: 'Office Desk — Standard', code: 'DESK-STD', categoryId: 'cat-3', categoryName: 'Office Furniture', qty: 22, reorder: 6, maxStock: 50, unit: 'Piece', cost: 70, price: 145);
    add(businessId: kDemoBusinessErbil, name: 'Ergonomic Office Chair', code: 'CHAIR-ERG', categoryId: 'cat-3', categoryName: 'Office Furniture', qty: 31, reorder: 10, maxStock: 60, unit: 'Piece', cost: 55, price: 110);
    add(businessId: kDemoBusinessErbil, name: 'Storage Shelving Unit', code: 'WH-SHELF-01', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 48, reorder: 12, maxStock: 120, unit: 'Set', cost: 85, price: 160, material: 'Steel');
    add(businessId: kDemoBusinessErbil, name: 'Pallet Rack Beam (2.7m)', code: 'WH-BEAM-27', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 9, reorder: 15, maxStock: 200, unit: 'Piece', cost: 32, price: 64, material: 'Steel');

    // City Storage Store (2 products).
    add(businessId: kDemoBusinessCityStore, name: 'Queen Bed Frame', code: 'BED-Q', categoryId: 'cat-2', categoryName: 'Bedroom', qty: 6, reorder: 4, maxStock: 25, unit: 'Piece', cost: 130, price: 260);
    add(businessId: kDemoBusinessCityStore, name: 'Plastic Storage Bin (60L)', code: 'ST-BIN-60', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 140, reorder: 30, maxStock: 300, unit: 'Piece', cost: 7, price: 15, material: 'Polypropylene');

    // Northern Distribution Center (2 products).
    add(businessId: kDemoBusinessNorthern, name: 'Stretch Wrap Roll', code: 'DC-WRAP-01', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 0, reorder: 20, maxStock: 250, unit: 'Piece', cost: 9, price: 18);
    add(businessId: kDemoBusinessNorthern, name: 'Shipping Carton (XL)', code: 'DC-BOX-XL', categoryId: 'cat-5', categoryName: 'Hardware & Fittings', qty: 380, reorder: 100, maxStock: 900, unit: 'Box', cost: 2, price: 5);
  }

  @override
  Future<PaginatedResult<Product>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Product>.from(_items);
    final categoryId = query.filters['categoryId'] as String?;
    if (categoryId != null) pool = pool.where((p) => p.categoryId == categoryId).toList();
    final status = query.filters['status'] as ProductStatus?;
    if (status != null) pool = pool.where((p) => p.status == status).toList();
    final type = query.filters['productType'] as ProductType?;
    if (type != null) pool = pool.where((p) => p.productType == type).toList();
    final stockFilter = query.filters['stock'] as String?;
    if (stockFilter == 'low') pool = pool.where((p) => p.isLowStock).toList();
    if (stockFilter == 'out') pool = pool.where((p) => p.isOutOfStock).toList();

    return paginateInMemory<Product>(
      pool,
      query,
      matches: (item, q) =>
          item.name.toLowerCase().contains(q) ||
          item.code.toLowerCase().contains(q) ||
          (item.sku?.toLowerCase().contains(q) ?? false) ||
          (item.barcode?.contains(q) ?? false),
      sortKey: (item) => item.name,
    );
  }

  @override
  Future<Product> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((p) => p.id == id, orElse: () => throw StateError('Product not found'));
  }

  @override
  Future<List<Product>> allForPicker() async {
    await simulatedLatency();
    return _items.where((p) => p.status == ProductStatus.active).toList();
  }

  @override
  Future<List<Product>> listForBusiness(String businessId) async {
    await simulatedLatency();
    return _items.where((p) => p.businessId == businessId).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Product _fromDraft(String id, ProductDraft draft, {required String businessId, required String categoryName, required DateTime createdAt}) {
    return Product(
      id: id,
      businessId: businessId,
      name: draft.name,
      code: draft.code,
      sku: draft.sku,
      barcode: draft.barcode,
      categoryId: draft.categoryId,
      categoryName: categoryName,
      brand: draft.brand,
      imageUrl: draft.imageUrl,
      description: draft.description,
      shortDescription: draft.shortDescription,
      status: draft.status,
      productType: draft.productType,
      currentQuantity: draft.currentQuantity,
      minStock: draft.minStock,
      maxStock: draft.maxStock,
      reorderLevel: draft.reorderLevel,
      warehouseName: draft.warehouseName,
      shelfRackBin: draft.shelfRackBin,
      unit: draft.unit,
      purchaseCost: draft.purchaseCost,
      sellingPrice: draft.sellingPrice,
      wholesalePrice: draft.wholesalePrice,
      discountPrice: draft.discountPrice,
      taxRate: draft.taxRate,
      size: draft.size,
      length: draft.length,
      width: draft.width,
      height: draft.height,
      weight: draft.weight,
      color: draft.color,
      material: draft.material,
      model: draft.model,
      manufacturer: draft.manufacturer,
      serialNumber: draft.serialNumber,
      batchNumber: draft.batchNumber,
      expiryDate: draft.expiryDate,
      warrantyPeriod: draft.warrantyPeriod,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<Product> create(ProductDraft draft) async {
    await simulatedLatency();
    // A real backend resolves categoryName server-side; the local repo
    // fakes the same lookup so the list/detail screens never see a blank
    // category label.
    final created = _fromDraft('prod-${_nextId++}', draft, businessId: kDemoBusinessForNewRecords, categoryName: _categoryNameFor(draft.categoryId), createdAt: DateTime.now());
    _items.add(created);
    return created;
  }

  @override
  Future<Product> update(String id, ProductDraft draft) async {
    await simulatedLatency();
    final index = _items.indexWhere((p) => p.id == id);
    if (index == -1) throw StateError('Product not found');
    final updated = _fromDraft(id, draft, businessId: _items[index].businessId, categoryName: _categoryNameFor(draft.categoryId), createdAt: _items[index].createdAt);
    _items[index] = updated;
    return updated;
  }

  @override
  Future<Product> adjustQuantity(String id, int delta) async {
    await simulatedLatency();
    final index = _items.indexWhere((p) => p.id == id);
    if (index == -1) throw StateError('Product not found');
    final current = _items[index];
    final draft = _draftFrom(current);
    final updated = _fromDraft(
      id,
      businessId: current.businessId,
      // Clamped at zero: demo stock going negative would make every
      // downstream figure (valuation, low-stock, the dashboard) nonsense.
      // `BusinessSettingsData.negativeInventoryAllowed` is the setting that
      // will decide this once the flows that honour it are wired.
      _draftWithQuantity(draft, (current.currentQuantity + delta).clamp(0, 1 << 31)),
      categoryName: current.categoryName,
      createdAt: current.createdAt,
    );
    _items[index] = updated;
    return updated;
  }

  ProductDraft _draftWithQuantity(ProductDraft draft, int quantity) => ProductDraft(
        name: draft.name,
        code: draft.code,
        sku: draft.sku,
        barcode: draft.barcode,
        categoryId: draft.categoryId,
        brand: draft.brand,
        imageUrl: draft.imageUrl,
        description: draft.description,
        shortDescription: draft.shortDescription,
        status: draft.status,
        productType: draft.productType,
        currentQuantity: quantity,
        minStock: draft.minStock,
        maxStock: draft.maxStock,
        reorderLevel: draft.reorderLevel,
        warehouseName: draft.warehouseName,
        shelfRackBin: draft.shelfRackBin,
        unit: draft.unit,
        purchaseCost: draft.purchaseCost,
        sellingPrice: draft.sellingPrice,
        wholesalePrice: draft.wholesalePrice,
        discountPrice: draft.discountPrice,
        taxRate: draft.taxRate,
      );

  @override
  Future<void> setStatus(String id, ProductStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((p) => p.id == id);
    if (index == -1) throw StateError('Product not found');
    final current = _items[index];
    final draft = _draftFrom(current);
    _items[index] = _fromDraft(
      id,
      businessId: current.businessId,
      ProductDraft(
        name: draft.name,
        code: draft.code,
        sku: draft.sku,
        barcode: draft.barcode,
        categoryId: draft.categoryId,
        brand: draft.brand,
        imageUrl: draft.imageUrl,
        description: draft.description,
        shortDescription: draft.shortDescription,
        status: status,
        productType: draft.productType,
        currentQuantity: draft.currentQuantity,
        minStock: draft.minStock,
        maxStock: draft.maxStock,
        reorderLevel: draft.reorderLevel,
        warehouseName: draft.warehouseName,
        shelfRackBin: draft.shelfRackBin,
        unit: draft.unit,
        purchaseCost: draft.purchaseCost,
        sellingPrice: draft.sellingPrice,
        wholesalePrice: draft.wholesalePrice,
        discountPrice: draft.discountPrice,
        taxRate: draft.taxRate,
      ),
      categoryName: current.categoryName,
      createdAt: current.createdAt,
    );
  }

  ProductDraft _draftFrom(Product p) => ProductDraft(
        name: p.name,
        code: p.code,
        sku: p.sku,
        barcode: p.barcode,
        categoryId: p.categoryId,
        brand: p.brand,
        imageUrl: p.imageUrl,
        description: p.description,
        shortDescription: p.shortDescription,
        status: p.status,
        productType: p.productType,
        currentQuantity: p.currentQuantity,
        minStock: p.minStock,
        maxStock: p.maxStock,
        reorderLevel: p.reorderLevel,
        warehouseName: p.warehouseName,
        shelfRackBin: p.shelfRackBin,
        unit: p.unit,
        purchaseCost: p.purchaseCost,
        sellingPrice: p.sellingPrice,
        wholesalePrice: p.wholesalePrice,
        discountPrice: p.discountPrice,
        taxRate: p.taxRate,
      );

  String _categoryNameFor(String categoryId) {
    // Demo-only convenience: the seeded categories from CategoryRepository
    // aren't reachable from here without an ugly cross-module import, so
    // this repeats the same small seed labels. A real API wouldn't need
    // this at all — the backend resolves the join.
    const names = {
      'cat-1': 'Living Room',
      'cat-2': 'Bedroom',
      'cat-3': 'Office Furniture',
      'cat-4': 'Raw Materials',
      'cat-5': 'Hardware & Fittings',
      'cat-6': 'Sofas',
      'cat-7': 'Coffee Tables',
      'cat-8': 'TV Units',
    };
    return names[categoryId] ?? categoryId;
  }
}
