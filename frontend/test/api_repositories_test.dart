// The wiring between each module's models and the real API's field names.
//
// This is the phase's actual risk. A repository that spells a field `name`
// where the server says `fullName`, or `return` where the enum says
// `returnMovement`, compiles perfectly and analyses clean — it just shows an
// empty name and the wrong movement type at runtime. Nothing but an assertion
// on the mapping catches it, so every field the screens depend on is pinned
// here, in both directions: what is parsed OUT of a response, and what is sent
// IN a request body.
//
// No network: Dio's adapter is replaced with a stub that answers from a map of
// canned responses and records every request it was given.

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/core/repositories/paged_query.dart';
import 'fakes/stub_api.dart';
import 'package:warehouse_os_app/features/customers/data/api_customer_repository.dart';
import 'package:warehouse_os_app/features/customers/data/customer_models.dart';
import 'package:warehouse_os_app/features/inventory/data/api_inventory_repository.dart';
import 'package:warehouse_os_app/features/inventory/data/inventory_models.dart';
import 'package:warehouse_os_app/features/orders/data/api_order_repository.dart';
import 'package:warehouse_os_app/features/orders/data/order_models.dart';
import 'package:warehouse_os_app/features/production/data/api_production_repository.dart';
import 'package:warehouse_os_app/features/production/data/production_models.dart';
import 'package:warehouse_os_app/features/purchases/data/api_purchase_repository.dart';
import 'package:warehouse_os_app/features/purchases/data/purchase_models.dart';
import 'package:warehouse_os_app/features/returns/data/api_return_repository.dart';
import 'package:warehouse_os_app/features/returns/data/return_models.dart';
import 'package:warehouse_os_app/features/suppliers/data/api_supplier_repository.dart';


void main() {
  group('Customers ↔ /api/customers', () {
    test('a customer row maps onto the fields the screens read', () async {
      final s = stubbedApi({
        'GET /customers': listEnvelope([
          {
            'id': 7,
            'code': 'CUS-0007',
            // The server says `name`; this module's model says `fullName`.
            'name': 'Ahmed Al-Rashid',
            'phone': '+9647701234567',
            'phoneSecondary': '+9647709999999',
            'email': 'a@example.com',
            'address': '12 Mill Road',
            'company': 'Rashid Trading',
            'notes': 'Prefers delivery',
            'status': 'active',
            // §18's derived totals, computed from orders and payments.
            'totalPurchases': 1250.5,
            'outstandingBalance': 300.25,
            'orderCount': 4,
            'createdAt': '2026-09-01T10:00:00.000Z',
          },
        ]),
      });

      final page = await ApiCustomerRepository(s.client).list(const PagedQuery());
      final customer = page.items.single;

      expect(customer.id, '7');
      expect(customer.fullName, 'Ahmed Al-Rashid');
      expect(customer.code, 'CUS-0007');
      expect(customer.secondaryPhone, '+9647709999999');
      expect(customer.company, 'Rashid Trading');
      expect(customer.status, CustomerStatus.active);
      expect(customer.totalPurchases, 1250.5);
      expect(customer.outstandingBalance, 300.25);
      expect(customer.orderCount, 4);
      expect(page.total, 1);
    });

    test('creating one sends `name`, not `fullName`', () async {
      final s = stubbedApi({
        'POST /customers': oneEnvelope({'id': 9, 'name': 'New Buyer', 'status': 'active'}),
      });

      await ApiCustomerRepository(s.client).create(
        const CustomerDraft(fullName: 'New Buyer', phone: '+9647700000000', company: 'Acme'),
      );

      final sent = s.stub.calls.single;
      expect(sent.method, 'POST');
      expect(sent.body!['name'], 'New Buyer', reason: 'the server has no fullName field');
      expect(sent.body!.containsKey('fullName'), isFalse);
      expect(sent.body!['company'], 'Acme');
    });

    test('applyOrder re-reads rather than writing totals the server derives', () async {
      final s = stubbedApi({
        'GET /customers/7': oneEnvelope({'id': 7, 'name': 'Ahmed', 'status': 'active', 'totalPurchases': 90.0}),
      });

      final customer = await ApiCustomerRepository(s.client).applyOrder(
        '7',
        grandTotal: 30,
        paidAmount: 10,
      );

      expect(customer.totalPurchases, 90.0, reason: 'the server computes this from the documents');
      expect(s.stub.calls.map((c) => c.method), ['GET'], reason: 'nothing may be written');
    });
  });

  group('Suppliers ↔ /api/suppliers', () {
    test("the server's totalPurchases is the supplier's purchase cost", () async {
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

      final supplier = (await ApiSupplierRepository(s.client).list(const PagedQuery())).items.single;
      expect(supplier.name, 'Erbil Timber Supply');
      expect(supplier.contactPerson, 'Sam');
      expect(supplier.totalPurchaseCost, 28400.0);
      expect(supplier.purchaseCount, 22);
    });
  });

  group('Inventory ↔ /api/inventory', () {
    test("§12's movement types survive the round trip, including `return`", () async {
      final s = stubbedApi({
        'GET /inventory/movements': listEnvelope([
          {
            'id': 11,
            'productId': 5,
            'productName': 'Oak Plank',
            // The API's word is `return`; the enum's is `returnMovement`.
            'movementType': 'return',
            'quantity': 2,
            'quantityBefore': 8,
            'quantityAfter': 10,
            'userName': 'Sarah',
            'movedAt': '2026-09-20T09:00:00.000Z',
            'locationName': 'A-1',
            'referenceNumber': 'RET-2026-000001',
            'note': 'Returned by customer',
          },
        ]),
      });

      final movement = (await ApiInventoryRepository(s.client).listMovements(const PagedQuery())).items.single;
      expect(movement.type, MovementType.returnMovement);
      expect(movement.productName, 'Oak Plank');
      expect(movement.previousQuantity, 8);
      expect(movement.newQuantity, 10);
      expect(movement.location, 'A-1');
      expect(movement.referenceNumber, 'RET-2026-000001');
      expect(movement.userName, 'Sarah');
    });

    test('a warehouse row maps its type, default flag and location count', () async {
      final s = stubbedApi({
        'GET /warehouses': listEnvelope([
          {
            'id': 2,
            'name': 'Production Floor',
            'locationType': 'production_area',
            'address': null,
            'isDefault': false,
            'locationCount': 3,
          },
        ]),
      });

      final warehouse = (await ApiInventoryRepository(s.client).listWarehouses()).single;
      expect(warehouse.name, 'Production Floor');
      expect(warehouse.type, 'Production area');
      expect(warehouse.isPrimary, isFalse);
      expect(warehouse.locationCount, 3);
    });

    test('a manual adjustment posts a SIGNED delta to the default warehouse', () async {
      final s = stubbedApi({
        'GET /warehouses/options': listEnvelope([
          {'id': 1, 'name': 'Overflow', 'isDefault': false},
          {'id': 2, 'name': 'Main', 'isDefault': true},
        ], total: 2),
        'POST /inventory/adjust': oneEnvelope({'productId': 5, 'after': 7}),
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

      final movement = await ApiInventoryRepository(s.client).recordAdjustment(
        productId: '5',
        productName: 'Oak Plank',
        currentQuantity: 10,
        delta: -3,
        type: MovementType.manualDecrease,
        note: 'Damaged in handling',
      );

      final adjust = s.stub.calls.firstWhere((c) => c.path == '/inventory/adjust');
      expect(adjust.body!['quantity'], -3, reason: 'the endpoint takes a delta, not a level');
      expect(adjust.body!['movementType'], 'manual_decrease');
      expect(adjust.body!['warehouseId'], 2, reason: 'the DEFAULT warehouse, not merely the first');
      expect(movement.newQuantity, 7, reason: 'read back from the ledger the server wrote');
    });

    test('a transfer without the product it moves is refused, not guessed', () async {
      // §11's DOCUMENT endpoint, not the bare two-legged movement: the list
      // reads transfers, so a movement filed the other way would move the
      // goods and then never appear in the list of transfers.
      final s = stubbedApi({
        'POST /stock-transfers': oneEnvelope({
          'id': 9,
          'transferNumber': 'TRF-2026-000009',
          'status': 'completed',
          'fromWarehouseName': 'Main',
          'toWarehouseName': 'Showroom',
        }),
      });

      // §8 does not make product names unique, so resolving one by name could
      // move a different product's stock.
      await expectLater(
        ApiInventoryRepository(s.client).createTransfer(
          fromWarehouseId: '1',
          toWarehouseId: '2',
          productName: 'Oak Plank',
          quantity: 5,
        ),
        throwsA(isA<StateError>()),
      );
      expect(s.stub.calls, isEmpty, reason: 'nothing may be sent on a guess');

      final created = await ApiInventoryRepository(s.client).createTransfer(
        fromWarehouseId: '1',
        toWarehouseId: '2',
        productName: 'Oak Plank',
        productId: '5',
        quantity: 5,
      );

      final body = s.stub.calls.single.body!;
      expect(body['fromWarehouseId'], 1);
      expect(body['toWarehouseId'], 2);
      expect((body['items'] as List).single, {'productId': 5, 'quantity': 5});
      expect(body['status'], 'completed', reason: 'the dialog records a move already made');
      expect(
        created.transferNumber,
        'TRF-2026-000009',
        reason: 'the document has a number — the ledger row it replaced never did',
      );
    });

    test('the transfer list reads documents, so a pending transfer is visible', () async {
      final s = stubbedApi({
        'GET /stock-transfers': listEnvelope([
          {
            'id': 9,
            'transferNumber': 'TRF-2026-000009',
            'status': 'pending',
            'fromWarehouseName': 'Main',
            'toWarehouseName': 'Showroom',
            'itemCount': 2,
            'totalQuantity': 12,
            'firstProductName': 'Oak Plank',
            'createdByName': 'Dara Salih',
            'createdAt': '2026-09-29 10:00:00',
            'note': 'Display set',
          },
        ]),
      });

      final page = await ApiInventoryRepository(s.client).listTransfers(const PagedQuery());
      final row = page.items.single;

      expect(row.status, TransferStatus.pending, reason: 'a ledger read could only ever show completed');
      expect(row.transferNumber, 'TRF-2026-000009');
      expect(row.quantity, 12, reason: 'the whole document, not one line');
      expect(row.productName, contains('Oak Plank'));
      expect(row.productName, contains('1 more'), reason: 'the other line is counted, not dropped');
      expect(row.requestedBy, 'Dara Salih');
    });
  });

  group('Orders ↔ /api/orders', () {
    test('a quick sale is confirmed so the stock leaves, then closed', () async {
      final s = stubbedApi({
        'POST /orders': oneEnvelope({'id': 21, 'orderNumber': 'INV-2026-000001', 'orderType': 'quick_sale'}),
        'POST /orders/21/payments': oneEnvelope({'paidAmount': 100.0}),
        'PATCH /orders/21/status': oneEnvelope({'id': 21, 'status': 'completed'}),
        'GET /orders/21': oneEnvelope({
          'id': 21,
          'orderNumber': 'INV-2026-000001',
          'orderType': 'quick_sale',
          'status': 'completed',
          'paidAmount': 100.0,
          'extraCharges': 0,
          'items': [
            {'productId': 5, 'productName': 'Oak Plank', 'quantity': 2, 'unitPrice': 50.0, 'taxAmount': 0},
          ],
        }),
      });

      final order = await ApiOrderRepository(s.client).create(
        const OrderDraft(
          orderType: OrderType.quickSale,
          items: [OrderItemDraft(productId: '5', productName: 'Oak Plank', quantity: 2, unitPrice: 50, tax: 4)],
          paidAmount: 100,
        ),
      );

      final created = s.stub.calls.firstWhere((c) => c.path == '/orders' && c.method == 'POST');
      expect(created.body!['orderType'], 'quick_sale');
      expect(
        created.body!['status'],
        'confirmed',
        reason: 'a quick sale hands the goods over now, and confirmation is when stock leaves',
      );
      // The form collects tax as an amount per line, not a rate.
      expect((created.body!['items'] as List).first['taxAmount'], 4);

      expect(
        s.stub.calls.any((c) => c.path == '/orders/21/payments'),
        isTrue,
        reason: '§43 records the money as its own row',
      );
      final closed = s.stub.calls.firstWhere((c) => c.path == '/orders/21/status');
      expect(closed.body!['status'], 'completed');
      expect(order.status, OrderStatus.completed);
      expect(order.items.single.productName, 'Oak Plank');
    });

    test('a standard order starts as a draft and moves nothing', () async {
      final s = stubbedApi({
        'POST /orders': oneEnvelope({'id': 22, 'orderType': 'standard'}),
        'GET /orders/22': oneEnvelope({'id': 22, 'orderType': 'standard', 'status': 'draft', 'items': []}),
      });

      await ApiOrderRepository(s.client).create(
        const OrderDraft(
          orderType: OrderType.standard,
          items: [OrderItemDraft(productId: '5', productName: 'Oak Plank', quantity: 1, unitPrice: 10)],
        ),
      );

      expect(s.stub.calls.first.body!['status'], 'draft');
      expect(
        s.stub.calls.any((c) => c.path.endsWith('/status')),
        isFalse,
        reason: 'a standard order is not completed on creation',
      );
    });

    test("the server's partially_returned reaches the enum", () async {
      final s = stubbedApi({
        'GET /orders': listEnvelope([
          {'id': 23, 'orderType': 'standard', 'status': 'partially_returned', 'paidAmount': 0, 'extraCharges': 0},
        ]),
      });

      final order = (await ApiOrderRepository(s.client).list(const PagedQuery())).items.single;
      expect(order.status, OrderStatus.partiallyReturned);
    });

    test('cancelling sends the reason §17 requires', () async {
      final s = stubbedApi({
        'PATCH /orders/24/status': oneEnvelope({'id': 24, 'status': 'cancelled'}),
        'GET /orders/24': oneEnvelope({'id': 24, 'orderType': 'standard', 'status': 'cancelled', 'items': []}),
      });

      await ApiOrderRepository(s.client).updateStatus('24', OrderStatus.cancelled);
      final sent = s.stub.calls.first;
      expect(sent.body!['status'], 'cancelled');
      expect(sent.body!['reason'], isNotNull, reason: '§17: a cancellation must say why');
    });
  });

  group('Purchases ↔ /api/purchases', () {
    test('a purchase row maps its supplier, money and payment method', () async {
      final s = stubbedApi({
        'GET /purchases/31': oneEnvelope({
          'id': 31,
          'purchaseNumber': 'PUR-2026-000001',
          'supplierId': 3,
          'supplierName': 'Erbil Timber Supply',
          'status': 'completed',
          'paidAmount': 1200.0,
          'note': 'First delivery',
          'purchaseDate': '2026-09-10T08:00:00.000Z',
          'payments': [{'method': 'bank_transfer', 'amount': 1200.0}],
          'items': [
            {'productId': 5, 'productName': 'Timber', 'quantity': 200, 'unitCost': 8.0, 'taxAmount': 80.0},
          ],
        }),
      });

      final purchase = await ApiPurchaseRepository(s.client).getById('31');
      expect(purchase.purchaseNumber, 'PUR-2026-000001');
      expect(purchase.supplierName, 'Erbil Timber Supply');
      expect(purchase.status, PurchaseStatus.completed);
      expect(purchase.paymentMethod, 'Bank transfer');
      expect(purchase.items.single.unitCost, 8.0);
      expect(purchase.items.single.tax, 80.0);
      expect(purchase.notes, 'First delivery');
    });

    test("a draft purchase reads as pending — the enum has no draft", () async {
      final s = stubbedApi({
        'GET /purchases': listEnvelope([{'id': 32, 'status': 'draft', 'paidAmount': 0}]),
      });
      final purchase = (await ApiPurchaseRepository(s.client).list(const PagedQuery())).items.single;
      expect(purchase.status, PurchaseStatus.pending);
    });

    test('creating one sends unitCost and the payment method as the API spells it', () async {
      final s = stubbedApi({
        'POST /purchases': oneEnvelope({'id': 33}),
        'GET /purchases/33': oneEnvelope({'id': 33, 'status': 'pending', 'items': []}),
      });

      await ApiPurchaseRepository(s.client).create(
        const PurchaseDraft(
          supplierId: '3',
          supplierName: 'Erbil Timber Supply',
          items: [PurchaseItemDraft(productId: '5', productName: 'Timber', quantity: 200, unitCost: 8, tax: 80)],
          paidAmount: 1200,
          paymentMethod: 'Bank transfer',
        ),
      );

      final sent = s.stub.calls.first;
      expect(sent.body!['supplierId'], 3);
      expect(sent.body!['paymentMethod'], 'bank_transfer');
      expect((sent.body!['items'] as List).first['unitCost'], 8);
      expect((sent.body!['items'] as List).first['taxAmount'], 80);
    });
  });

  group('Returns ↔ /api/returns', () {
    test('a return resolves the ORDER LINE it is against', () async {
      final s = stubbedApi({
        'GET /orders/41/returnable': oneEnvelope({
          'orderId': 41,
          'returnable': true,
          'lines': [
            {'id': 501, 'productId': 5, 'productName': 'Chair', 'quantity': 4, 'returned': 0, 'remaining': 4},
            {'id': 502, 'productId': 6, 'productName': 'Table', 'quantity': 1, 'returned': 0, 'remaining': 1},
          ],
        }),
        'POST /returns': oneEnvelope({'id': 42}),
        'GET /returns/42': oneEnvelope({
          'id': 42,
          'returnNumber': 'RET-2026-000001',
          'orderId': 41,
          'orderNumber': 'ORD-2026-000001',
          'status': 'requested',
          'reason': 'Wrong colour',
          'refundAmount': 200.0,
          'items': [{'productId': 5, 'productName': 'Chair', 'quantity': 2, 'condition': 'sellable'}],
        }),
      });

      final returned = await ApiReturnRepository(s.client).create(
        const ReturnDraft(
          orderId: '41',
          orderNumber: 'ORD-2026-000001',
          items: [ReturnItemDraft(productId: '5', productName: 'Chair', quantity: 2, condition: ItemCondition.sellable)],
          reason: 'Wrong colour',
          refundAmount: 200,
        ),
      );

      final sent = s.stub.calls.firstWhere((c) => c.path == '/returns');
      final line = (sent.body!['items'] as List).single as Map<String, dynamic>;
      expect(line['orderItemId'], 501, reason: 'the line for product 5, not the product id itself');
      expect(line['quantity'], 2);
      expect(line['condition'], 'sellable');
      expect(returned.status, ReturnStatus.requested);
      expect(returned.refundAmount, 200.0);
    });

    test('a damaged condition survives, since it decides whether stock comes back', () async {
      final s = stubbedApi({
        'GET /returns/43': oneEnvelope({
          'id': 43,
          'orderId': 41,
          'status': 'completed',
          'reason': 'Broken',
          'refundAmount': 100.0,
          'items': [{'productId': 5, 'productName': 'Chair', 'quantity': 1, 'condition': 'damaged'}],
        }),
      });

      final returned = await ApiReturnRepository(s.client).getById('43');
      expect(returned.items.single.condition, ItemCondition.damaged);
      expect(
        returned.restocksOnCompletion,
        isFalse,
        reason: '§16: a damaged item must not read as restocking',
      );
    });

    test('a product that is not on the order is refused before anything is sent', () async {
      final s = stubbedApi({
        'GET /orders/41/returnable': oneEnvelope({'orderId': 41, 'returnable': true, 'lines': []}),
      });

      await expectLater(
        ApiReturnRepository(s.client).create(
          const ReturnDraft(
            orderId: '41',
            orderNumber: 'ORD-2026-000001',
            items: [ReturnItemDraft(productId: '9', productName: 'Ghost', quantity: 1, condition: ItemCondition.sellable)],
            reason: 'Nope',
            refundAmount: 0,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(s.stub.calls.any((c) => c.method == 'POST'), isFalse);
    });
  });

  group('Production ↔ /api/production-orders', () {
    test("a run's materials are the batch's own snapshot, not the recipe", () async {
      final s = stubbedApi({
        'GET /production-orders/51': oneEnvelope({
          'id': 51,
          'productionNumber': 'PRD-2026-000001',
          'productId': 5,
          'productName': 'Table',
          'status': 'completed',
          'quantityPlanned': 10,
          'quantityProduced': 8,
          'productionCost': 290.0,
          'batchNumber': 'B-1',
          'startedAt': '2026-09-20T08:00:00.000Z',
          'completedAt': '2026-09-20T17:00:00.000Z',
          'materials': [
            {
              'materialProductId': 6,
              'materialProductName': 'Wood',
              // Already multiplied out for the batch.
              'quantityRequired': 50,
              'quantityConsumed': 50,
              'unitCost': 5.0,
              'unitCode': 'pcs',
            },
          ],
        }),
      });

      final run = await ApiProductionRepository(s.client).getById('51');
      expect(run.productionNumber, 'PRD-2026-000001');
      expect(run.status, ProductionStatus.completed);
      expect(run.quantityPlanned, 10);
      expect(run.quantityProduced, 8, reason: '§22 keeps planned and produced apart');
      expect(run.cost, 290.0);
      expect(run.batchNumber, 'B-1');
      expect(run.materials.single.materialProductName, 'Wood');
      expect(run.materials.single.quantityRequired, 50);
      expect(run.materials.single.unit, 'pcs');
    });

    test('the bill of materials is read per unit', () async {
      final s = stubbedApi({
        'GET /products/5/bom': oneEnvelope({
          'productId': 5,
          'productName': 'Table',
          'lines': [
            {'materialProductId': 6, 'materialProductName': 'Wood', 'quantityPerUnit': 5, 'unitCode': 'pcs'},
            {'materialProductId': 7, 'materialProductName': 'Paint', 'quantityPerUnit': 2, 'unitCode': 'L'},
          ],
        }),
      });

      final bom = await ApiProductionRepository(s.client).bomFor('5');
      expect(bom.length, 2);
      expect(bom.first.quantityRequired, 5, reason: 'the recipe is per unit; the run scales it');
      expect(bom.last.materialProductName, 'Paint');
      expect(bom.last.unit, 'L');
    });

    test('in_progress round-trips through the enum', () async {
      final s = stubbedApi({
        'PATCH /production-orders/52/status': oneEnvelope({'id': 52}),
        'GET /production-orders/52': oneEnvelope({
          'id': 52,
          'productId': 5,
          'status': 'in_progress',
          'quantityPlanned': 5,
          'quantityProduced': 0,
          'materials': [],
        }),
      });

      final run = await ApiProductionRepository(s.client).updateStatus('52', ProductionStatus.inProgress);
      expect(s.stub.calls.first.body!['status'], 'in_progress');
      expect(run.status, ProductionStatus.inProgress);
    });
  });
}
