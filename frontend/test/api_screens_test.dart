// The SCREENS, driven by the real Api*Repository classes.
//
// `api_repositories_test.dart` proves each repository parses the server's
// fields. This proves the screens then render them: it mounts the real app,
// overrides each module's repository with its API implementation behind a
// stubbed HTTP layer, navigates to the module, and looks for the values the
// server sent on the screen — then taps a row and checks the detail view asks
// for and shows the right record.
//
// This is the closest thing to clicking through the app in backend mode that
// runs unattended. It is what catches a screen that reads a field the wiring
// leaves null, which no repository test can see.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/core/config/app_mode.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/inventory/data/inventory_models.dart';
import 'package:warehouse_os_app/features/inventory/data/stock_engine.dart';
import 'package:warehouse_os_app/features/orders/data/order_models.dart';
import 'package:warehouse_os_app/features/customers/data/api_customer_repository.dart';
import 'package:warehouse_os_app/features/customers/data/customer_providers.dart';
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
import 'package:warehouse_os_app/features/suppliers/data/api_supplier_repository.dart';
import 'package:warehouse_os_app/features/suppliers/data/supplier_providers.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/routing/app_router.dart';

import 'fakes/fake_auth.dart';
import 'fakes/stub_api.dart';

void main() {
  /// Mounts the real app on a desktop-width view with `container`'s overrides,
  /// then navigates to `route`.
  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, {required String route}) async {
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
    await tester.pumpAndSettle();

    container.read(routerProvider).go(route);
    await tester.pumpAndSettle();
  }

  testWidgets('Customers: the list shows what the API sent', (tester) async {
    final s = stubbedApi({
      'GET /customers': listEnvelope([
        {
          'id': 7,
          'code': 'CUS-0007',
          'name': 'Ahmed Al-Rashid',
          'phone': '+9647701234567',
          'company': 'Rashid Trading',
          'status': 'active',
          'totalPurchases': 1250.5,
          'outstandingBalance': 300.25,
          'orderCount': 4,
          'createdAt': '2026-09-01T10:00:00.000Z',
        },
      ]),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          customerRepositoryProvider.overrideWithValue(ApiCustomerRepository(s.client)),
        ],
      ),
      route: AppRoutes.customers,
    );

    expect(find.text('Ahmed Al-Rashid'), findsWidgets);
    expect(
      s.stub.calls.any((c) => c.path.startsWith('/customers')),
      isTrue,
      reason: 'the screen must have asked the API, not demo data',
    );
  });

  testWidgets('Suppliers: the list shows what the API sent', (tester) async {
    final s = stubbedApi({
      'GET /suppliers': listEnvelope([
        {
          'id': 3,
          'name': 'Erbil Timber Supply',
          'company': 'Erbil Timber Co.',
          'phone': '+9647501112233',
          'contactPerson': 'Sam',
          'status': 'active',
          'totalPurchases': 28400.0,
          'outstandingBalance': 2000.0,
          'purchaseCount': 22,
          'createdAt': '2026-08-01T10:00:00.000Z',
        },
      ]),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          supplierRepositoryProvider.overrideWithValue(ApiSupplierRepository(s.client)),
        ],
      ),
      route: AppRoutes.suppliers,
    );

    expect(find.text('Erbil Timber Supply'), findsWidgets);
  });

  testWidgets("Orders: the list shows the API's order, and a tap opens its detail", (tester) async {
    final s = stubbedApi({
      'GET /orders': listEnvelope([
        {
          'id': 21,
          'orderNumber': 'ORD-2026-000021',
          'orderType': 'standard',
          'status': 'confirmed',
          'customerId': 7,
          'customerName': 'Ahmed Al-Rashid',
          'paidAmount': 100.0,
          'extraCharges': 0,
          'grandTotal': 400.0,
          'itemCount': 1,
          'orderDate': '2026-09-20T10:00:00.000Z',
        },
      ]),
      'GET /orders/21': oneEnvelope({
        'id': 21,
        'orderNumber': 'ORD-2026-000021',
        'orderType': 'standard',
        'status': 'confirmed',
        'customerId': 7,
        'customerName': 'Ahmed Al-Rashid',
        'paidAmount': 100.0,
        'extraCharges': 0,
        'items': [
          {
            'productId': 5,
            'productName': 'Oak Plank',
            'quantity': 4,
            'unitPrice': 100.0,
            'discountAmount': 0,
            'taxAmount': 0,
            'lineTotal': 400.0,
          },
        ],
      }),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          orderRepositoryProvider.overrideWithValue(ApiOrderRepository(s.client)),
        ],
      ),
      route: AppRoutes.orders,
    );

    expect(find.text('ORD-2026-000021'), findsWidgets);

    await tester.tap(find.text('ORD-2026-000021').first);
    await tester.pumpAndSettle();

    // The detail screen reads the order again, with its lines — §55's snapshot.
    expect(
      s.stub.calls.any((c) => c.path == '/orders/21'),
      isTrue,
      reason: 'opening an order must fetch it with its lines',
    );
    expect(find.text('Oak Plank'), findsWidgets, reason: 'the line the API sent must be on screen');
  });

  testWidgets("Purchases: the list shows the API's purchase, and a tap opens its detail", (tester) async {
    final s = stubbedApi({
      'GET /purchases': listEnvelope([
        {
          'id': 31,
          'purchaseNumber': 'PUR-2026-000031',
          'supplierId': 3,
          'supplierName': 'Erbil Timber Supply',
          'status': 'pending',
          'paidAmount': 0,
          'total': 1600.0,
          'remainingAmount': 1600.0,
          'paymentStatus': 'unpaid',
          'itemCount': 1,
          'purchaseDate': '2026-09-18T10:00:00.000Z',
        },
      ]),
      'GET /purchases/31': oneEnvelope({
        'id': 31,
        'purchaseNumber': 'PUR-2026-000031',
        'supplierId': 3,
        'supplierName': 'Erbil Timber Supply',
        'status': 'pending',
        'paidAmount': 0,
        'total': 1600.0,
        'items': [
          {
            'productId': 5,
            'productName': 'Solid Pine Timber',
            'quantity': 200,
            'unitCost': 8.0,
            'discountAmount': 0,
            'taxAmount': 0,
            'lineTotal': 1600.0,
          },
        ],
      }),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          purchaseRepositoryProvider.overrideWithValue(ApiPurchaseRepository(s.client)),
        ],
      ),
      route: AppRoutes.purchases,
    );

    expect(find.text('PUR-2026-000031'), findsWidgets);

    await tester.tap(find.text('PUR-2026-000031').first);
    await tester.pumpAndSettle();

    expect(s.stub.calls.any((c) => c.path == '/purchases/31'), isTrue);
    expect(find.text('Solid Pine Timber'), findsWidgets);
  });

  testWidgets("Returns: the list shows the API's return", (tester) async {
    final s = stubbedApi({
      'GET /returns': listEnvelope([
        {
          'id': 42,
          'returnNumber': 'RET-2026-000042',
          'orderId': 21,
          'orderNumber': 'ORD-2026-000021',
          'customerName': 'Ahmed Al-Rashid',
          'status': 'requested',
          'reason': 'Wrong colour',
          'refundAmount': 200.0,
          'itemCount': 1,
          'returnDate': '2026-09-21T10:00:00.000Z',
        },
      ]),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          returnRepositoryProvider.overrideWithValue(ApiReturnRepository(s.client)),
        ],
      ),
      route: AppRoutes.returns,
    );

    expect(find.text('RET-2026-000042'), findsWidgets);
  });

  testWidgets("Production: the list shows the API's run", (tester) async {
    final s = stubbedApi({
      'GET /production-orders': listEnvelope([
        {
          'id': 51,
          'productionNumber': 'PRD-2026-000051',
          'productId': 5,
          'productName': 'Dining Table',
          'status': 'planned',
          'quantityPlanned': 10,
          'quantityProduced': 0,
          'productionCost': 290.0,
          'batchNumber': 'B-1',
          'materialCount': 2,
          'createdAt': '2026-09-22T10:00:00.000Z',
        },
      ]),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          productionRepositoryProvider.overrideWithValue(ApiProductionRepository(s.client)),
        ],
      ),
      route: AppRoutes.production,
    );

    expect(find.text('PRD-2026-000051'), findsWidgets);
  });

  // ---- the double-count guard, exercised through the screens ---------------
  //
  // StockEngine moves stock client-side and is called from these screens. In
  // backend mode the server has already moved it as part of the status change,
  // so the engine must not move it again — that was the defect that would have
  // doubled every quantity. These drive the real status-change flows with the
  // mode set to backend and assert the shape of what left the app: the status
  // PATCH, and nothing else that would touch stock.

  /// Everything `OrderDetailScreen._transition` does for a status change: the
  /// status call, then the engine for the stock that follows it.
  ///
  /// Driven directly rather than by tapping the button, because after the tap
  /// the screen's own reload spinner keeps scheduling frames and
  /// `pumpAndSettle` never returns. The production code under test is the same
  /// — the real repository and the real engine — and the list-to-detail tap is
  /// covered by the Orders test above.
  test('Confirming an order sends the status change and does NOT also adjust stock', () async {
    final s = stubbedApi({
      'GET /orders': listEnvelope([
        {
          'id': 21,
          'orderNumber': 'ORD-2026-000021',
          'orderType': 'standard',
          'status': 'pending',
          'paidAmount': 0,
          'extraCharges': 0,
          'grandTotal': 400.0,
          'itemCount': 1,
          'orderDate': '2026-09-20T10:00:00.000Z',
        },
      ]),
      'GET /orders/21': oneEnvelope({
        'id': 21,
        'orderNumber': 'ORD-2026-000021',
        'orderType': 'standard',
        'status': 'confirmed',
        'paidAmount': 0,
        'extraCharges': 0,
        'items': [
          {
            'productId': 5,
            'productName': 'Oak Plank',
            'quantity': 4,
            'unitPrice': 100.0,
            'discountAmount': 0,
            'taxAmount': 0,
            'lineTotal': 400.0,
          },
        ],
      }),
      'PATCH /orders/21/status': oneEnvelope({'id': 21, 'status': 'confirmed'}),
      // Deliberately stubbed so a stray client-side adjustment would SUCCEED
      // rather than fail — the assertion is that it never happens, not that it
      // errors.
      'POST /inventory/adjust': oneEnvelope({'after': 0}),
      'GET /warehouses/options': listEnvelope([{'id': 1, 'name': 'Main', 'isDefault': true}]),
      'GET /inventory/movements': listEnvelope([]),
      'GET /products': listEnvelope([]),
    });

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(FakeAuthenticatedController.new),
        appModeProvider.overrideWithValue(AppMode.backend),
        orderRepositoryProvider.overrideWithValue(ApiOrderRepository(s.client)),
        inventoryRepositoryProvider.overrideWithValue(ApiInventoryRepository(s.client)),
        productRepositoryProvider.overrideWithValue(ApiProductRepository(s.client)),
      ],
    );
    addTearDown(container.dispose);

    final order = await container.read(orderRepositoryProvider).updateStatus('21', OrderStatus.confirmed);
    await container.read(stockEngineProvider).apply(
      [const StockChange(productId: '5', productName: 'Oak Plank', delta: -4)],
      type: MovementType.sale,
      note: order.orderNumber,
    );
    // Let the engine's provider refreshes finish while the container is alive.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      s.stub.calls.any((c) => c.method == 'PATCH' && c.path == '/orders/21/status'),
      isTrue,
      reason: 'the status change must reach the server',
    );
    expect(
      s.stub.calls.any((c) => c.path == '/inventory/adjust'),
      isFalse,
      reason: 'the SERVER moves stock on confirmation — moving it here as well would double it',
    );
  });

  // A plain `test`, not `testWidgets`: the engine's demo path awaits the demo
  // repositories' simulated latency, and a real `Future.delayed` never
  // completes inside `testWidgets` unless the harness pumps.
  test('A manual adjustment reaches the API in backend mode — exactly once', () async {
    // The other half of the same rule, and the bug it caught: nothing but this
    // path records a manual adjustment, so it must not be skipped — but it must
    // also not be applied twice. `/inventory/adjust` moves the level AND writes
    // the ledger row, and `ApiProductRepository.adjustQuantity` routes through
    // the same endpoint, so calling both posted the same delta twice and a
    // decrease of three took six.
    final s = stubbedApi({
      'GET /warehouses/options': listEnvelope([{'id': 1, 'name': 'Main', 'isDefault': true}]),
      'POST /inventory/adjust': oneEnvelope({'after': 7}),
      'GET /products': listEnvelope([]),
      'GET /inventory/movements': listEnvelope([
        {
          'id': 12,
          'productId': 5,
          'productName': 'Oak Plank',
          'movementType': 'manual_decrease',
          'quantity': 3,
          'quantityBefore': 10,
          'quantityAfter': 7,
          'userName': 'Sarah',
          'movedAt': '2026-09-20T09:30:00.000Z',
        },
      ]),
    });

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(FakeAuthenticatedController.new),
        appModeProvider.overrideWithValue(AppMode.backend),
        inventoryRepositoryProvider.overrideWithValue(ApiInventoryRepository(s.client)),
        // The products repository must be the API one too, or this test would
        // pass against demo data and never see the second write.
        productRepositoryProvider.overrideWithValue(ApiProductRepository(s.client)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(stockEngineProvider).apply(
      [const StockChange(productId: '5', productName: 'Oak Plank', delta: -3)],
      type: MovementType.manualDecrease,
      note: 'Damaged in handling',
    );

    // Let the engine's provider refreshes finish while the container is alive.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final adjustments = s.stub.calls.where((c) => c.method == 'POST' && c.path == '/inventory/adjust');
    expect(
      adjustments.length,
      1,
      reason: "a manual adjustment is the user's own action, recorded once — not once per store",
    );
    expect(adjustments.single.body!['quantity'], -3, reason: 'and for the amount asked, not double');
  });

  testWidgets("Inventory: the movements view shows the API's ledger rows", (tester) async {
    final s = stubbedApi({
      'GET /inventory/movements': listEnvelope([
        {
          'id': 11,
          'productId': 5,
          'productName': 'Oak Plank',
          'movementType': 'return',
          'quantity': 2,
          'quantityBefore': 8,
          'quantityAfter': 10,
          'userName': 'Sarah',
          'movedAt': '2026-09-20T09:00:00.000Z',
          'locationName': 'A-1',
          'referenceNumber': 'RET-2026-000001',
        },
      ]),
      'GET /warehouses': listEnvelope([
        {
          'id': 1,
          'name': 'Main Warehouse',
          'locationType': 'warehouse',
          'address': 'Industrial Zone',
          'isDefault': true,
          'locationCount': 12,
        },
      ]),
    });

    await pumpApp(
      tester,
      ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          inventoryRepositoryProvider.overrideWithValue(ApiInventoryRepository(s.client)),
        ],
      ),
      route: AppRoutes.inventory,
    );

    // The module opens on stock overview; §12's ledger is the second tab, so
    // this goes where a user would go to read it.
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();

    expect(
      s.stub.calls.any((c) => c.path.startsWith('/inventory/movements')),
      isTrue,
      reason: 'the ledger must come from the API',
    );
    expect(find.text('Oak Plank'), findsWidgets, reason: 'the ledger row the API sent must be listed');
    expect(
      find.text('RET-2026-000001'),
      findsWidgets,
      reason: 'and so must the document it came from — §12 records the reference',
    );
  });
}
