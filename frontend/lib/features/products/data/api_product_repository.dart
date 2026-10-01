import '../../../core/network/api_client.dart';
import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../categories/data/api_category_repository.dart' show buildListQuery;
import 'product_models.dart';
import 'product_repository.dart';

/// Products against the real backend (§8).
///
/// THIS CLASS IS WHERE TWO KNOWN MISMATCHES ARE RECONCILED, deliberately in
/// one place rather than by changing the app's models:
///
///  1. STATUS. The database uses §45's own word, `archived`; the Flutter
///     enum says `discontinued`. They mean the same lifecycle state, so
///     they are translated here. Changing either side would have been the
///     tidier fix, but it touches either the specification's vocabulary or
///     ten screens.
///
///  2. QUANTITIES. The database stores DECIMAL(14,3) — 2.5 kg is a real
///     quantity — while the Flutter models are `int`. Values are rounded on
///     the way in. A fractional quantity therefore DISPLAYS rounded in this
///     app, though it is stored exactly; converting the models to `double`
///     is a separate, larger change (~34 declarations, ~17 display files).
///
/// Both are recorded in docs rather than left as folklore.
class ApiProductRepository implements ProductRepository {
  ApiProductRepository(this._client);

  final ApiClient _client;

  static const _statusToApi = {
    ProductStatus.active: 'active',
    ProductStatus.inactive: 'inactive',
    ProductStatus.discontinued: 'archived',
  };

  /// Public because it is a pure mapping worth testing directly: it is the
  /// only place that knows §45's "archived" and the app's "discontinued"
  /// are the same state.
  static ProductStatus statusFromApi(String? value) => switch (value) {
    'inactive' => ProductStatus.inactive,
    'archived' => ProductStatus.discontinued,
    _ => ProductStatus.active,
  };

  static ProductType _typeFromApi(String? value) =>
      value == 'raw_material' ? ProductType.rawMaterial : ProductType.finishedGood;

  static String _typeToApi(ProductType type) => switch (type) {
    ProductType.rawMaterial => 'raw_material',
    // The backend has no `component`: §21 names two kinds, and a component
    // is a raw material as far as production is concerned.
    ProductType.component => 'raw_material',
    ProductType.finishedGood => 'finished_good',
  };

  static int _int(Object? value) => value == null ? 0 : (value as num).round();
  static int? _intOrNull(Object? value) => value == null ? null : (value as num).round();
  static double? _double(Object? value) => value == null ? null : (value as num).toDouble();

  static Product _fromJson(Map<String, dynamic> json) => Product(
    id: '${json['id']}',
    // The API never returns another tenant's rows, so the business is
    // whoever is signed in; the field exists for the admin drill-down.
    businessId: '${json['businessId'] ?? ''}',
    name: (json['name'] as String?) ?? '',
    code: (json['productCode'] as String?) ?? '',
    sku: json['sku'] as String?,
    barcode: json['barcode'] as String?,
    categoryId: json['categoryId'] == null ? '' : '${json['categoryId']}',
    categoryName: (json['categoryName'] as String?) ?? '',
    brand: json['brand'] as String?,
    imageUrl: json['imageUrl'] as String?,
    description: json['description'] as String?,
    shortDescription: json['shortDescription'] as String?,
    status: statusFromApi(json['status'] as String?),
    productType: _typeFromApi(json['productType'] as String?),
    currentQuantity: _int(json['currentQuantity']),
    minStock: _intOrNull(json['minStock']),
    maxStock: _intOrNull(json['maxStock']),
    reorderLevel: _intOrNull(json['reorderLevel']),
    reservedQuantity: _int(json['reservedQuantity']),
    warehouseName: json['warehouseName'] as String?,
    shelfRackBin: json['shelfRackBin'] as String?,
    unit: (json['unitName'] as String?) ?? (json['unitCode'] as String?) ?? '',
    // Absent unless the caller holds §24's financial.view — the model's
    // field is nullable, so a user without it simply sees no cost.
    purchaseCost: _double(json['purchaseCost']),
    sellingPrice: _double(json['sellingPrice']),
    wholesalePrice: _double(json['wholesalePrice']),
    discountPrice: _double(json['discountPrice']),
    taxRate: _double(json['taxRate']),
    size: json['size'] as String?,
    length: _double(json['length']),
    width: _double(json['width']),
    height: _double(json['height']),
    weight: _double(json['weight']),
    color: json['color'] as String?,
    material: json['material'] as String?,
    model: json['model'] as String?,
    manufacturer: json['manufacturer'] as String?,
    serialNumber: json['serialNumber'] as String?,
    batchNumber: json['batchNumber'] as String?,
    expiryDate: json['expiryDate'] == null ? null : DateTime.tryParse('${json['expiryDate']}'),
    warrantyPeriod: json['warrantyPeriod'] as String?,
    createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
  );

  /// `currentQuantity` is deliberately NOT sent: a product's stock is the
  /// sum of what sits in its locations, and the backend refuses to let the
  /// product form set it. Stock changes go through the inventory endpoints.
  /// Public for the same reason as [statusFromApi] — the enum folding and
  /// the deliberate absence of a quantity field are both worth pinning.
  static Map<String, dynamic> toRequestJson(ProductDraft draft) => {
    'name': draft.name,
    'productCode': draft.code,
    'sku': draft.sku,
    'barcode': draft.barcode,
    'categoryId': int.tryParse(draft.categoryId),
    'status': _statusToApi[draft.status],
    'productType': _typeToApi(draft.productType),
    'minStock': draft.minStock,
    'maxStock': draft.maxStock,
    'reorderLevel': draft.reorderLevel,
    'purchaseCost': draft.purchaseCost,
    'sellingPrice': draft.sellingPrice,
    'wholesalePrice': draft.wholesalePrice,
    'discountPrice': draft.discountPrice,
    'taxRate': draft.taxRate,
    'brand': draft.brand,
    'imageUrl': draft.imageUrl,
    'description': draft.description,
    'shortDescription': draft.shortDescription,
    'size': draft.size,
    'length': draft.length,
    'width': draft.width,
    'height': draft.height,
    'weight': draft.weight,
    'color': draft.color,
    'material': draft.material,
    'model': draft.model,
    'manufacturer': draft.manufacturer,
    'serialNumber': draft.serialNumber,
    'batchNumber': draft.batchNumber,
    'expiryDate': draft.expiryDate?.toIso8601String().split('T').first,
    'warrantyPeriod': draft.warrantyPeriod,
  };

  @override
  Future<PaginatedResult<Product>> list(PagedQuery query) async {
    final result = await _client.getList('/products?${buildListQuery(query)}');
    final page = result.meta['pagination'] as Map<String, dynamic>?;
    return PaginatedResult(
      items: result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList(),
      page: (page?['page'] as int?) ?? query.page,
      pageSize: (page?['pageSize'] as int?) ?? query.pageSize,
      total: (page?['total'] as int?) ?? result.data.length,
    );
  }

  @override
  Future<Product> getById(String id) async => _fromJson(await _client.getJson('/products/$id'));

  @override
  Future<Product> create(ProductDraft draft) async =>
      _fromJson(await _client.postJson('/products', toRequestJson(draft)));

  @override
  Future<Product> update(String id, ProductDraft draft) async =>
      _fromJson(await _client.patchJson('/products/$id', toRequestJson(draft)));

  @override
  Future<void> setStatus(String id, ProductStatus status) async {
    await _client.patchJson('/products/$id', {'status': _statusToApi[status]});
  }

  @override
  Future<Product> adjustQuantity(String id, int delta) async {
    // Routed through the inventory endpoint, never by writing a quantity
    // onto the product: §12 requires the level and the ledger to move
    // together, and only that endpoint does both.
    //
    // It needs a warehouse, which this interface does not carry — so the
    // business's default warehouse is used, which is what §11's "default"
    // is for. A caller that needs a specific location uses the inventory
    // API directly.
    final warehouses = await _client.getList('/warehouses/options');
    if (warehouses.data.isEmpty) {
      throw StateError('No warehouse exists yet. Create one before adjusting stock.');
    }
    final defaultWarehouse = warehouses.data.firstWhere(
      (w) => (w as Map<String, dynamic>)['isDefault'] == true,
      orElse: () => warehouses.data.first,
    ) as Map<String, dynamic>;

    await _client.postJson('/inventory/adjust', {
      'productId': int.tryParse(id),
      'warehouseId': defaultWarehouse['id'],
      'quantity': delta,
      'movementType': delta > 0 ? 'manual_increase' : 'manual_decrease',
      'reason': 'Adjusted from the product screen',
    });

    return getById(id);
  }

  @override
  Future<List<Product>> allForPicker() async {
    // Active products only, in one page large enough for a picker. The
    // backend caps pageSize at 100, so this is the cap rather than "all" —
    // a business with more than 100 products needs a searchable picker,
    // which is a UI change rather than a repository one.
    final result = await _client.getList('/products?status=active&pageSize=100&sort=name&direction=asc');
    return result.data.map((row) => _fromJson(row as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Product>> listForBusiness(String businessId) async {
    // §57's System Admin drill-down, through the endpoint that names the
    // business. A business-side route is scoped to the caller's own session
    // (§36) and a System Admin has no session-scoped business, so this is a
    // deliberate admin endpoint rather than the same one with a wider scope.
    //
    // It answers with the same field names the business-side view uses, so
    // these rows map with exactly the same code as any other product.
    final response = await _client.getJson('/admin/businesses/$businessId/products');
    return ((response['items'] as List<dynamic>?) ?? const [])
        .map((row) => _fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
