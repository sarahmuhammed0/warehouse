// The whole app, every repository pointed at the real Api* implementation,
// behind one stubbed HTTP layer that answers every endpoint the app calls.
//
// `api_screens_test.dart` builds a container per test with just the two or
// three repositories that test needs. That is right for a focused test and
// wrong for asking "does every screen render" — which needs all of them at
// once, and needs an answer for any endpoint any screen might reach.
//
// So the stub here has a CATCH-ALL: an unrecognised GET answers with an empty
// list rather than a 404. That matters. A 404 surfaces as a Failure, every
// screen shows its error state, and a sweep over all the routes would pass
// while proving nothing about rendering. An empty list is what a real business
// with no rows yet returns, so a screen that cannot cope with one is a screen
// with a real bug.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/core/config/app_mode.dart';
import 'package:warehouse_os_app/core/network/api_client.dart';
import 'package:warehouse_os_app/core/network/providers.dart';
import 'package:warehouse_os_app/features/activity_history/data/api_audit_repository.dart';
import 'package:warehouse_os_app/features/activity_history/data/audit_providers.dart';
import 'package:warehouse_os_app/features/admin/data/admin_providers.dart';
import 'package:warehouse_os_app/features/admin/data/api_admin_repository.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/categories/data/api_category_repository.dart';
import 'package:warehouse_os_app/features/categories/data/category_providers.dart';
import 'package:warehouse_os_app/features/customers/data/api_customer_repository.dart';
import 'package:warehouse_os_app/features/customers/data/customer_providers.dart';
import 'package:warehouse_os_app/features/employees/data/api_employee_repository.dart';
import 'package:warehouse_os_app/features/employees/data/employee_providers.dart';
import 'package:warehouse_os_app/features/inventory/data/api_inventory_repository.dart';
import 'package:warehouse_os_app/features/inventory/data/inventory_providers.dart';
import 'package:warehouse_os_app/features/orders/data/api_order_repository.dart';
import 'package:warehouse_os_app/features/orders/data/order_providers.dart';
import 'package:warehouse_os_app/features/production/data/api_production_repository.dart';
import 'package:warehouse_os_app/features/production/data/production_providers.dart';
import 'package:warehouse_os_app/features/products/data/api_product_repository.dart';
import 'package:warehouse_os_app/features/products/data/product_providers.dart';
import 'package:warehouse_os_app/features/purchases/data/api_purchase_repository.dart';
import 'package:warehouse_os_app/features/purchases/data/purchase_providers.dart';
import 'package:warehouse_os_app/features/returns/data/api_return_repository.dart';
import 'package:warehouse_os_app/features/returns/data/return_providers.dart';
import 'package:warehouse_os_app/features/settings/data/backup_repository.dart';
import 'package:warehouse_os_app/features/settings/data/custom_fields_repository.dart';
import 'package:warehouse_os_app/features/settings/data/settings_repository.dart';
import 'package:warehouse_os_app/features/settings/data/settings_state.dart';
import 'package:warehouse_os_app/features/suppliers/data/api_supplier_repository.dart';
import 'package:warehouse_os_app/features/suppliers/data/supplier_providers.dart';
import 'package:warehouse_os_app/routing/app_router.dart';

import 'fake_auth.dart';

/// One recorded call, so a test can assert what was SENT.
class RecordedCall {
  RecordedCall(this.method, this.path, this.body, {String? fullPath}) : fullPath = fullPath ?? path;
  final String method;

  /// Without the query string — what the stub map is keyed on.
  final String path;

  /// With it. Kept because some contracts live entirely in the query: whether
  /// the global search actually sent its term, which page was asked for, how a
  /// list was sorted. Matching only on [path] would let a search that forgot
  /// its term pass, which is the defect `global_search_test.dart` exists for.
  final String fullPath;

  final Map<String, dynamic>? body;

  @override
  String toString() => '$method $fullPath';
}

class FullStubAdapter implements HttpClientAdapter {
  FullStubAdapter(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<RecordedCall> calls = [];

  /// Paths asked for that the fixture has no entry for. Printed by
  /// [expectNoUnstubbedReads] so a screen reaching an endpoint nobody thought
  /// about shows up as a finding rather than as an empty table.
  final Set<String> unstubbed = {};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data is Map<String, dynamic> ? options.data as Map<String, dynamic> : null;
    final path = options.path.split('?').first;
    calls.add(RecordedCall(options.method, path, body, fullPath: options.path));

    final envelope = responses['${options.method} $path'];
    if (envelope != null) return _json(envelope);

    unstubbed.add('${options.method} $path');

    // The catch-all. A GET gets an empty page; anything else gets an empty
    // object, which is a successful write that changed nothing.
    return _json(
      options.method == 'GET'
          ? {'success': true, 'data': const [], 'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 0}}}
          : {'success': true, 'data': const <String, dynamic>{}},
    );
  }

  ResponseBody _json(Map<String, dynamic> envelope) => ResponseBody.fromString(
    jsonEncode(envelope),
    200,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _list(List<Map<String, dynamic>> rows) => {
  'success': true,
  'data': rows,
  'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': rows.length}},
};

Map<String, dynamic> _one(Map<String, dynamic> row) => {'success': true, 'data': row};

/// Distinctive values, so a test can assert a screen is showing the SERVER's
/// data and not something it made up. Each is unlikely to appear by accident.
const fixtureProductName = 'Oak Dining Table';
const fixtureCustomerName = 'Ahmed Al-Rashid';
const fixtureSupplierName = 'Zagros Timber';
const fixtureOrderNumber = 'ORD-2026-000001';
const fixtureSaleNumber = 'INV-2026-000001';
const fixturePurchaseNumber = 'PUR-2026-000001';
const fixtureReturnNumber = 'RET-2026-000001';
const fixtureRunNumber = 'PRDN-2026-000001';
const fixtureTransferNumber = 'TRF-2026-000001';
const fixtureStaffName = 'Dara Salih';
const fixtureBusinessName = 'Karwan Furniture Factory';
const fixtureCategoryName = 'Dining Furniture';
const fixtureAuditDescription = 'Created product "Oak Dining Table"';
const fixtureNotificationTitle = 'Low stock';
const fixtureCustomFieldLabel = 'Wood type';

/// One realistic row per endpoint the app reads.
Map<String, Map<String, dynamic>> fullBackendFixture() {
  final product = {
    'id': 5,
    'businessId': 1,
    'name': fixtureProductName,
    'productCode': 'PRD-0005',
    'sku': 'TBL-OAK-180',
    'categoryId': 3,
    'categoryName': fixtureCategoryName,
    'status': 'active',
    'productType': 'finished_good',
    'currentQuantity': 12,
    'reservedQuantity': 0,
    'reorderLevel': 4,
    'minStock': 2,
    'unitName': 'Piece',
    'sellingPrice': 320.0,
    'purchaseCost': 180.0,
    'warehouseName': 'Main Warehouse',
    'createdAt': '2026-09-28 20:39:25',
  };

  final order = {
    'id': 21,
    'businessId': 1,
    'orderNumber': fixtureOrderNumber,
    'orderType': 'standard',
    'status': 'confirmed',
    'paymentStatus': 'partially_paid',
    'customerId': 7,
    'customerName': fixtureCustomerName,
    'grandTotal': 1302.0,
    'paidAmount': 500.0,
    'extraCharges': 0,
    'orderDate': '2026-09-28 20:39:28',
    'createdByName': fixtureStaffName,
    'items': [
      {'productId': 5, 'productName': fixtureProductName, 'quantity': 2, 'unitPrice': 320.0, 'taxAmount': 32.0, 'discountAmount': 0},
    ],
    'payments': [
      {'id': 1, 'method': 'cash', 'amount': 500.0, 'paidAt': '2026-09-28 20:40:00'},
    ],
  };

  final sale = {...order, 'id': 22, 'orderNumber': fixtureSaleNumber, 'orderType': 'quick_sale', 'status': 'completed'};

  return {
    // ── Products, categories ───────────────────────────────────────────────
    'GET /products': _list([product]),
    'GET /products/5': _one(product),
    'GET /products/5/variants': _list([
      {'id': 31, 'sku': 'TBL-OAK-180-W', 'sellingPrice': 340.0, 'purchaseCost': 190.0, 'attributes': {'label': 'Finish: White'}, 'quantity': 3},
    ]),
    'GET /products/5/bom': _list([
      {'materialProductId': 9, 'materialName': 'Oak Plank', 'quantityPerUnit': 4.0, 'unitName': 'Piece'},
    ]),
    'GET /categories': _list([
      {'id': 3, 'name': fixtureCategoryName, 'parentId': null, 'status': 'active', 'productCount': 4, 'createdAt': '2026-09-28 20:39:00'},
    ]),
    'GET /categories/options': _list([{'id': 3, 'name': fixtureCategoryName, 'parentId': null}]),
    'GET /units': _list([{'id': 1, 'name': 'Piece', 'code': 'pc'}]),
    'GET /units/options': _list([{'id': 1, 'name': 'Piece', 'code': 'pc'}]),

    // ── Inventory ──────────────────────────────────────────────────────────
    'GET /inventory': _list([
      {'id': 1, 'productId': 5, 'productName': fixtureProductName, 'warehouseId': 2, 'warehouseName': 'Main Warehouse', 'quantity': 12, 'unitName': 'Piece'},
    ]),
    'GET /inventory/movements': _list([
      {
        'id': 100, 'productId': 5, 'productName': fixtureProductName, 'movementType': 'manual_increase',
        'quantity': 5.0, 'quantityBefore': 7.0, 'quantityAfter': 12.0, 'warehouseName': 'Main Warehouse',
        'userName': fixtureStaffName, 'note': 'Stock count', 'movedAt': '2026-09-28 21:00:00',
      },
    ]),
    'GET /warehouses': _list([{'id': 2, 'name': 'Main Warehouse', 'isDefault': true, 'status': 'active'}]),
    'GET /warehouses/options': _list([{'id': 2, 'name': 'Main Warehouse', 'isDefault': true}]),
    'GET /storage-locations': _list([{'id': 8, 'name': 'Rack A1', 'warehouseId': 2, 'warehouseName': 'Main Warehouse'}]),
    'GET /stock-transfers': _list([
      {
        'id': 84, 'transferNumber': fixtureTransferNumber, 'status': 'pending',
        'fromWarehouseName': 'Main Warehouse', 'toWarehouseName': 'City Showroom',
        'itemCount': 1, 'totalQuantity': 8.0, 'firstProductName': fixtureProductName,
        'createdByName': fixtureStaffName, 'note': 'Showroom display', 'createdAt': '2026-09-28 20:39:27',
      },
    ]),

    // ── Parties ────────────────────────────────────────────────────────────
    'GET /customers': _list([
      {'id': 7, 'code': 'CUS-0007', 'name': fixtureCustomerName, 'phone': '+9647701112233', 'status': 'active', 'totalPurchases': 1302.0, 'outstandingBalance': 802.0, 'orderCount': 2, 'createdAt': '2026-09-28 20:39:00'},
    ]),
    'GET /customers/7': _one({'id': 7, 'code': 'CUS-0007', 'name': fixtureCustomerName, 'phone': '+9647701112233', 'status': 'active', 'totalPurchases': 1302.0, 'outstandingBalance': 802.0, 'orderCount': 2, 'createdAt': '2026-09-28 20:39:00'}),
    'GET /suppliers': _list([
      {'id': 4, 'code': 'SUP-0004', 'name': fixtureSupplierName, 'phone': '+9647705556677', 'status': 'active', 'totalPurchases': 900.0, 'outstandingBalance': 0.0, 'purchaseCount': 1, 'createdAt': '2026-09-28 20:39:00'},
    ]),
    'GET /suppliers/4': _one({'id': 4, 'code': 'SUP-0004', 'name': fixtureSupplierName, 'phone': '+9647705556677', 'status': 'active', 'totalPurchases': 900.0, 'outstandingBalance': 0.0, 'purchaseCount': 1, 'createdAt': '2026-09-28 20:39:00'}),

    // ── Documents ──────────────────────────────────────────────────────────
    'GET /orders': _list([order, sale]),
    'GET /orders/21': _one(order),
    'GET /orders/22': _one(sale),
    'GET /orders/21/returnable': _list([
      {'orderItemId': 55, 'productId': 5, 'productName': fixtureProductName, 'quantity': 2.0, 'returnedQuantity': 0.0, 'remainingQuantity': 2.0, 'unitPrice': 320.0},
    ]),
    'GET /purchases': _list([
      {'id': 31, 'purchaseNumber': fixturePurchaseNumber, 'supplierId': 4, 'supplierName': fixtureSupplierName, 'status': 'received', 'grandTotal': 900.0, 'paidAmount': 900.0, 'extraCharges': 0, 'purchaseDate': '2026-09-28 20:39:26', 'createdByName': fixtureStaffName, 'items': [{'productId': 9, 'productName': 'Oak Plank', 'quantity': 50, 'unitPrice': 18.0, 'taxAmount': 0, 'discountAmount': 0}]},
    ]),
    'GET /purchases/31': _one({'id': 31, 'purchaseNumber': fixturePurchaseNumber, 'supplierId': 4, 'supplierName': fixtureSupplierName, 'status': 'received', 'grandTotal': 900.0, 'paidAmount': 900.0, 'extraCharges': 0, 'purchaseDate': '2026-09-28 20:39:26', 'createdByName': fixtureStaffName, 'items': [{'productId': 9, 'productName': 'Oak Plank', 'quantity': 50, 'unitPrice': 18.0, 'taxAmount': 0, 'discountAmount': 0}]}),
    'GET /returns': _list([
      {'id': 12, 'returnNumber': fixtureReturnNumber, 'orderId': 21, 'orderNumber': fixtureOrderNumber, 'customerName': fixtureCustomerName, 'status': 'pending', 'refundAmount': 320.0, 'returnDate': '2026-09-29 09:00:00', 'createdByName': fixtureStaffName, 'items': [{'productId': 5, 'productName': fixtureProductName, 'quantity': 1, 'unitPrice': 320.0, 'condition': 'sellable'}]},
    ]),
    'GET /returns/12': _one({'id': 12, 'returnNumber': fixtureReturnNumber, 'orderId': 21, 'orderNumber': fixtureOrderNumber, 'customerName': fixtureCustomerName, 'status': 'pending', 'refundAmount': 320.0, 'returnDate': '2026-09-29 09:00:00', 'createdByName': fixtureStaffName, 'items': [{'productId': 5, 'productName': fixtureProductName, 'quantity': 1, 'unitPrice': 320.0, 'condition': 'sellable'}]}),
    'GET /production-orders': _list([
      {'id': 6, 'productionNumber': fixtureRunNumber, 'productId': 5, 'productName': fixtureProductName, 'status': 'completed', 'quantityToProduce': 4.0, 'quantityProduced': 4.0, 'startDate': '2026-09-28 20:39:27', 'createdByName': fixtureStaffName, 'materials': [{'materialProductId': 9, 'materialName': 'Oak Plank', 'quantityRequired': 16.0, 'unitName': 'Piece'}]},
    ]),
    'GET /production-orders/6': _one({'id': 6, 'productionNumber': fixtureRunNumber, 'productId': 5, 'productName': fixtureProductName, 'status': 'completed', 'quantityToProduce': 4.0, 'quantityProduced': 4.0, 'startDate': '2026-09-28 20:39:27', 'createdByName': fixtureStaffName, 'materials': [{'materialProductId': 9, 'materialName': 'Oak Plank', 'quantityRequired': 16.0, 'unitName': 'Piece'}]}),

    // ── Staff, roles, trail ────────────────────────────────────────────────
    'GET /users': _list([
      {'id': 8552, 'businessId': 1, 'name': fixtureStaffName, 'phone': '+9647500000011', 'email': null, 'roleId': 12, 'roleName': 'Warehouse Manager', 'status': 'active', 'lastLoginAt': '2026-09-29 08:00:00', 'createdAt': '2026-09-28 20:39:00'},
    ]),
    'GET /users/8552': _one({'id': 8552, 'businessId': 1, 'name': fixtureStaffName, 'phone': '+9647500000011', 'email': null, 'roleId': 12, 'roleName': 'Warehouse Manager', 'status': 'active', 'createdAt': '2026-09-28 20:39:00'}),
    'GET /roles': _list([
      {'id': 11, 'name': 'Business Owner/Admin', 'isSystemRole': true, 'permissions': ['products.view', 'users.view'], 'userCount': 1},
      {'id': 12, 'name': 'Warehouse Manager', 'isSystemRole': true, 'permissions': ['inventory.view', 'products.view'], 'userCount': 3},
    ]),
    'GET /roles/permissions': _list([
      {'key': 'products.view', 'module': 'products', 'action': 'view', 'description': 'View products'},
    ]),
    'GET /audit-logs': _list([
      {'id': 900, 'actorName': fixtureStaffName, 'module': 'products', 'action': 'product.create', 'description': fixtureAuditDescription, 'ipAddress': '10.0.0.4', 'referenceId': 5, 'createdAt': '2026-09-28 21:10:00'},
    ]),
    'GET /audit-logs/actions': _list([{'module': 'products', 'action': 'product.create'}]),

    // ── Notifications ──────────────────────────────────────────────────────
    'GET /notifications': _list([
      {'id': 5, 'type': 'low_stock', 'title': fixtureNotificationTitle, 'body': '$fixtureProductName: 2 left.', 'referenceType': 'products', 'referenceId': 5, 'isRead': false, 'readAt': null, 'createdAt': '2026-09-29 10:00:00'},
    ]),
    'GET /notifications/unread-count': _one({'unread': 1}),

    // ── Settings ───────────────────────────────────────────────────────────
    'GET /business': _one({'id': 1, 'name': fixtureBusinessName, 'currency': 'IQD', 'businessType': 'furniture_factory'}),
    'GET /settings': _one({
      'values': {
        'inventory.allow_negative_stock': false,
        'inventory.low_stock_threshold_default': 6,
        'payments.cash_enabled': true,
        'payments.bank_transfer_enabled': true,
        'payments.card_enabled': false,
        'security.min_password_length': 9,
      },
    }),
    'GET /documents/numbering': _list([
      {'documentType': 'sale', 'prefix': 'INV', 'nextNumber': 42, 'numberPadding': 6, 'includeYear': true, 'example': 'INV-2026-000042'},
      {'documentType': 'order', 'prefix': 'ORD', 'nextNumber': 8, 'numberPadding': 6, 'includeYear': true, 'example': 'ORD-2026-000008'},
      {'documentType': 'purchase', 'prefix': 'PUR', 'nextNumber': 2, 'numberPadding': 6, 'includeYear': true, 'example': 'PUR-2026-000002'},
      {'documentType': 'production', 'prefix': 'PRDN', 'nextNumber': 3, 'numberPadding': 6, 'includeYear': true, 'example': 'PRDN-2026-000003'},
    ]),
    'GET /documents/pdf-template': _one({
      'footerText': 'Thank you for your business.',
      'fields': {'logo': true, 'taxInfo': true, 'signature': true, 'paymentTerms': true, 'returnPolicy': false, 'thankYou': true, 'customerAddress': true, 'itemSku': true},
      'availableFields': ['logo', 'taxInfo', 'signature', 'paymentTerms', 'returnPolicy', 'thankYou', 'customerAddress', 'itemSku'],
    }),
    'GET /custom-fields': _list([
      {'id': 3, 'entityType': 'product', 'label': fixtureCustomFieldLabel, 'fieldKey': 'wood_type', 'fieldType': 'text', 'isVisible': true, 'sortOrder': 0},
    ]),

    // ── Reports ────────────────────────────────────────────────────────────
    'GET /reports': _list([{'key': 'sales_summary', 'name': 'Sales summary', 'requiresFinancial': true}]),

    // ── Health ─────────────────────────────────────────────────────────────
    'GET /health': _one({'status': 'ok', 'uptime': 1234.5, 'environment': 'development', 'version': '0.0.0'}),
    'GET /health/db': _one({'status': 'ok', 'reachable': true, 'latencyMs': 3}),

    // ── System Admin ───────────────────────────────────────────────────────
    'GET /admin/businesses': _list([
      {'id': 1, 'name': fixtureBusinessName, 'businessType': 'furniture_factory', 'phone': '+9647500000003', 'status': 'active', 'createdAt': '2026-09-28 20:39:24', 'owner': {'id': 2, 'name': 'Karwan Ahmed', 'phone': '+9647500000002'}},
    ]),
    'GET /admin/businesses/1': _one({'id': 1, 'name': fixtureBusinessName, 'businessType': 'furniture_factory', 'phone': '+9647500000003', 'email': null, 'address': null, 'status': 'active', 'createdAt': '2026-09-28 20:39:24', 'counts': {'users': 5, 'products': 4, 'orders': 2}}),
    'GET /admin/businesses/1/users': _one({'items': [{'id': 8552, 'businessId': 1, 'name': fixtureStaffName, 'phone': '+9647500000011', 'roleId': 12, 'roleName': 'Warehouse Manager', 'status': 'active', 'createdAt': '2026-09-28 20:39:00'}], 'limit': 200, 'truncated': false}),
    'GET /admin/businesses/1/products': _one({'items': [product], 'limit': 200, 'truncated': false}),
    'GET /admin/businesses/1/orders': _one({'items': [order], 'limit': 200, 'truncated': false}),
    'GET /admin/businesses/1/reports': _one({'businessId': 1, 'counts': {'users': 5, 'products': 4, 'customers': 2, 'suppliers': 2, 'orders': 2, 'purchases': 1}, 'totals': {'salesTotal': 1452.0, 'stockQuantity': 120.0}, 'recentOrders': [{'orderNumber': fixtureOrderNumber, 'status': 'confirmed', 'total': 1302.0, 'orderDate': '2026-09-28 20:39:28'}]}),
    'GET /admin/activity': _list([
      {'id': 1, 'businessId': 1, 'businessName': fixtureBusinessName, 'module': 'auth', 'action': 'auth.login_success', 'description': 'Login succeeded.', 'createdAt': '2026-09-29 16:44:31'},
    ]),
    'GET /admin/backups': _list([
      {'id': 1, 'status': 'pending', 'sizeBytes': null, 'errorMessage': 'No configured backup target.', 'createdAt': '2026-09-29 12:00:00'},
    ]),
    'GET /admin/registrations': _list([]),
  };
}

/// The app, signed in, every repository pointed at the stubbed API.
///
/// The override list is built inline rather than returned from a helper:
/// Riverpod 3 does not export `Override`, so there is no type to annotate a
/// `List<Override>` with.
({ProviderContainer container, FullStubAdapter stub}) apiBackedApp({
  Map<String, Map<String, dynamic>>? extraResponses,
  bool asAdmin = false,
}) {
  final stub = FullStubAdapter({...fullBackendFixture(), ...?extraResponses});
  final client = ApiClient();
  client.dio.httpClientAdapter = stub;

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        asAdmin ? FakeAdminAuthenticatedController.new : FakeAuthenticatedController.new,
      ),
      appModeProvider.overrideWithValue(AppMode.backend),
      // The client itself, so anything that builds its own repository from it
      // reaches the stub too — the notification centre, the variant list, the
      // health check. Overriding only the repositories left those three talking
      // to a real HTTP client, which in flutter_test answers 400 and which the
      // variant list then swallowed, so its fetch silently never happened.
      apiClientProvider.overrideWithValue(client),
      productRepositoryProvider.overrideWithValue(ApiProductRepository(client)),
      categoryRepositoryProvider.overrideWithValue(ApiCategoryRepository(client)),
      inventoryRepositoryProvider.overrideWithValue(ApiInventoryRepository(client)),
      customerRepositoryProvider.overrideWithValue(ApiCustomerRepository(client)),
      supplierRepositoryProvider.overrideWithValue(ApiSupplierRepository(client)),
      orderRepositoryProvider.overrideWithValue(ApiOrderRepository(client)),
      purchaseRepositoryProvider.overrideWithValue(ApiPurchaseRepository(client)),
      returnRepositoryProvider.overrideWithValue(ApiReturnRepository(client)),
      productionRepositoryProvider.overrideWithValue(ApiProductionRepository(client)),
      employeeRepositoryProvider.overrideWithValue(ApiEmployeeRepository(client)),
      auditRepositoryProvider.overrideWithValue(ApiAuditRepository(client)),
      adminRepositoryProvider.overrideWithValue(ApiAdminRepository(client)),
      settingsRepositoryProvider.overrideWithValue(ApiSettingsRepository(client)),
      customFieldsRepositoryProvider.overrideWithValue(ApiCustomFieldsRepository(client)),
      backupRepositoryProvider.overrideWithValue(ApiBackupRepository(client)),
    ],
  );
  return (container: container, stub: stub);
}

/// Mounts the app at [route] on a desktop-width view.
/// Mounts the app at [route] on a desktop-width view.
///
/// [settle] false pumps for a fixed time instead of waiting for the tree to go
/// quiet. Needed when a test deliberately makes an endpoint fail: the app passes
/// through the dashboard on the way to [route], and a dashboard whose own data
/// is refused keeps scheduling frames, so `pumpAndSettle` times out on scenery
/// rather than on the screen under test.
Future<void> pumpAppAt(
  WidgetTester tester,
  ProviderContainer container,
  String route, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 2));
  }

  container.read(routerProvider).go(route);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  }
}
