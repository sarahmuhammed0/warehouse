// Reported from production: "everytime i add a product no matter how many are
// the stocks for that product when saved it is zero and out of stock".
//
// The form offered an editable "Current quantity", collected it into the draft,
// and then dropped it. `toRequestJson` deliberately does not send it and the
// server would refuse it anyway — a product's stock is the sum of what sits in
// its locations, never a column somebody writes — so the typed number went
// nowhere and the product landed OUT OF STOCK with nothing saying why.
//
// The fix is not to send it on the product. It is to put it where stock
// actually lives: `/inventory/adjust`, which moves the level and writes the
// ledger row together (§12). These prove the number gets there, that an edit
// moves by the DIFFERENCE rather than re-adding the whole figure, and that a
// business with nowhere to put stock is told so instead of silently saving a
// zero.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  Finder field(String key) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextFormField));

  Future<void> fillAndSave(WidgetTester tester, {required String quantity}) async {
    await tester.enterText(field('productName'), 'Walnut Shelf');
    await tester.enterText(field('productCode'), 'WS-001');
    await tester.enterText(field('productQuantity'), quantity);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('productSave'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  List<RecordedCall> adjustments(FullStubAdapter stub) =>
      stub.calls.where((c) => c.method == 'POST' && c.path == '/inventory/adjust').toList();

  group('the quantity typed on the product form becomes real stock', () {
    testWidgets('creating with 50 puts 50 through the inventory endpoint', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'POST /products': {'success': true, 'data': {'id': 77, 'name': 'Walnut Shelf'}},
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productNew);

      await fillAndSave(tester, quantity: '50');

      final posted = adjustments(app.stub);
      expect(posted, hasLength(1), reason: 'the typed opening stock has to go somewhere');
      expect(posted.single.body!['productId'], 77, reason: 'onto the product that was just created');
      expect(posted.single.body!['quantity'], 50);
      expect(posted.single.body!['movementType'], 'manual_increase');
    });

    testWidgets('creating with 0 moves no stock and writes no ledger row', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'POST /products': {'success': true, 'data': {'id': 78, 'name': 'Walnut Shelf'}},
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productNew);

      await fillAndSave(tester, quantity: '0');

      expect(
        adjustments(app.stub),
        isEmpty,
        reason: 'a product that starts empty is not a stock movement, and must not invent a ledger row',
      );
    });
  });

  group('editing moves stock by the difference, not the whole figure again', () {
    testWidgets('raising 12 to 20 records a +8', (tester) async {
      // The fixture product holds 12.
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/products/5/edit');

      await tester.enterText(field('productQuantity'), '20');
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('productSave'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      final posted = adjustments(app.stub);
      expect(posted, hasLength(1));
      expect(posted.single.body!['quantity'], 8, reason: '20 - 12, not another 20');
    });

    testWidgets('leaving the box alone changes nothing', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/products/5/edit');

      // Edit a different field entirely.
      await tester.enterText(field('productName'), 'Oak Dining Table (renamed)');
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('productSave'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        adjustments(app.stub),
        isEmpty,
        reason: 'renaming a product is not a stock movement',
      );
    });
  });

  group('when the stock cannot be placed, it is said out loud', () {
    testWidgets('a business with no warehouse is told, and the product is still saved', (tester) async {
      // `adjustQuantity` asks for the warehouses first and refuses when there
      // are none. That was the original "stock does not apply" fault; here it
      // must surface rather than leave a silent zero.
      final app = apiBackedApp(extraResponses: {
        'POST /products': {'success': true, 'data': {'id': 79, 'name': 'Walnut Shelf'}},
        'GET /warehouses/options': {
          'success': true,
          'data': const [],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 0}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productNew);

      await fillAndSave(tester, quantity: '50');

      expect(adjustments(app.stub), isEmpty, reason: 'there was nowhere to put it');
      // The exact sentence, not merely something containing "warehouse" — the
      // products list has its own columns and would make that pass for free.
      expect(
        find.text('No warehouse exists yet. Create one before adjusting stock.'),
        findsOneWidget,
        reason: 'the reason is shown; a silently saved zero is what was reported in the first place',
      );
      expect(
        app.stub.calls.where((c) => c.method == 'POST' && c.path == '/products'),
        hasLength(1),
        reason: 'and the product itself was still created, so the save is not lost',
      );
    });
  });
}
