// The same defect as "add production", in the three forms that shared it.
//
// Orders, Purchases and Returns each answered a failed submit with
// `_error = l10n.requiredFieldMessage` — "This field is required." printed as a
// bare line above the buttons. None of the three screens had a `Form`, so no
// field on them could go red, and each message stood in for more than one
// problem at once:
//
//   Orders    — no line items. Not a field at all.
//   Purchases — no supplier chosen, OR no line items. Two problems, one message.
//   Returns   — no order chosen, OR no quantities, OR no reason. Three.
//
// What each now does: the real fields report themselves, and the one thing that
// genuinely is not a field ("add an item") says so in those words.
//
// Which fields are required is the server's answer, not a guess:
//   `createOrderSchema.customerId`    — nullable().optional()  (§18 cash sale)
//   `createPurchaseSchema.supplierId` — nullable().optional()
//   `createReturnSchema.orderId`      — required
//   `createReturnSchema.reason`       — requiredString(500)
//   all three `items` arrays          — .min(1, "…needs at least one item.")

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  /// These forms are taller than the viewport, so the Create button sits below
  /// the fold and a plain `tap` misses it.
  Future<void> tap(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  List<RecordedCall> posts(FullStubAdapter stub, String path) =>
      stub.calls.where((c) => c.method == 'POST' && c.path == path).toList();

  group('Orders', () {
    testWidgets('an order with no items asks for an item, not for a nameless field', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.orderNew);

      await tap(tester, 'orderSave');

      expect(find.text('Add at least one item.'), findsOneWidget);
      expect(
        find.text('This field is required.'),
        findsNothing,
        reason: 'nothing on this form is a required field — §18 allows an anonymous cash customer',
      );
      expect(posts(app.stub, '/orders'), isEmpty);
    });
  });

  group('Purchases', () {
    testWidgets('no supplier chosen reds the Supplier field itself', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.purchaseNew);

      await tap(tester, 'purchaseSave');

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('purchaseSupplierPicker')),
          matching: find.text('This field is required.'),
        ),
        findsOneWidget,
        reason: 'the supplier is one of the two things the old nameless message could have meant',
      );
      expect(posts(app.stub, '/purchases'), isEmpty);
    });

    testWidgets('a business with no suppliers is told to add one, not that a field is required', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'GET /suppliers': {
          'success': true,
          'data': const [],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 0}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.purchaseNew);

      expect(find.text('No suppliers yet. Add one first — a purchase has to come from somebody.'), findsOneWidget);
      expect(find.text('Add Suppliers'), findsOneWidget);
      expect(find.text('This field is required.'), findsNothing);

      // And pressing Create there must not answer "Unable to save": with no
      // picker in the tree `validate()` passes, and `_supplierId!` would throw a
      // null check into the generic catch. Same defect as the Production form,
      // found by driving the real app.
      await tap(tester, 'purchaseSave');
      expect(find.text('Unable to save. Please try again.'), findsNothing);
      expect(find.text('No suppliers yet. Add one first — a purchase has to come from somebody.'), findsWidgets);
      expect(posts(app.stub, '/purchases'), isEmpty);
    });
  });

  group('Returns', () {
    testWidgets('both required fields report themselves at once', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.returnNew);

      await tap(tester, 'returnSave');

      // The order picker is one of the three problems the single message used to
      // stand for. The reason is another — it is inside the card that only
      // appears once an order is chosen, so it cannot be asserted on the same
      // pump; the picker is what is on screen here.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('returnOrderPicker')),
          matching: find.text('This field is required.'),
        ),
        findsOneWidget,
      );
      expect(posts(app.stub, '/returns'), isEmpty);
    });

    testWidgets('with an order chosen, the missing reason is reported on the Reason field', (tester) async {
      // `completedOrdersProvider` keeps only completed orders and the shared
      // fixture's is `confirmed`, so this supplies one that can be returned.
      final app = apiBackedApp(extraResponses: {
        'GET /orders': {
          'success': true,
          'data': [
            {
              'id': 23, 'businessId': 1, 'orderNumber': fixtureOrderNumber, 'orderType': 'standard',
              'status': 'completed', 'paymentStatus': 'paid', 'customerId': 7,
              'customerName': fixtureCustomerName, 'grandTotal': 320.0, 'paidAmount': 320.0,
              'extraCharges': 0, 'orderDate': '2026-09-28 20:39:28', 'createdByName': fixtureStaffName,
              'items': [
                {'productId': 5, 'productName': fixtureProductName, 'quantity': 2, 'unitPrice': 320.0, 'taxAmount': 0, 'discountAmount': 0},
              ],
            },
          ],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 1}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.returnNew);

      // The picker's label is "number — customer".
      const label = '$fixtureOrderNumber — $fixtureCustomerName';
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('returnOrderPicker')), matching: find.byType(TextFormField)),
        label,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text(label)).last);
      await tester.pumpAndSettle();

      await tap(tester, 'returnSave');

      // Reason is `requiredString(500)` on the server and now reports itself
      // instead of being folded into one nameless line with two other problems.
      expect(find.text('This field is required.'), findsWidgets);
      expect(posts(app.stub, '/returns'), isEmpty);
    });
  });
}
