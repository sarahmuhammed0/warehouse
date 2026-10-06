// "Add production" reported as: *"everytime i add one and apply all field keeps
// saying this field is required, and it doesnt show which exatly, + i already
// filled all and still"*.
//
// Three separate defects produced that one sentence, and all three are driven
// here through the real screen, the real router and the real repository behind
// the stubbed API:
//
//   1. The required check was a hand-rolled `_error = l10n.requiredFieldMessage`
//      printed as a bare line above the buttons. It named no field, and the
//      Product picker it was about was neither marked nor reddened — the screen
//      had no `Form` at all, so no field on it could show an error.
//   2. It fired on `_product == null`, which is also what a business with no
//      finished products has. The picker was empty, nothing could be chosen,
//      and the form answered "This field is required." instead of "go make a
//      product first" — unfillable, and silent about why.
//   3. The Employee box was collected and then left out of the request
//      entirely, so the assignment was dropped on every run ever created. The
//      operator had indeed "filled all" of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  /// The one required picker on the screen.
  Finder productField() => find.byKey(const ValueKey('productionProductPicker'));
  Finder quantityField() =>
      find.descendant(of: find.byKey(const ValueKey('productionQuantity')), matching: find.byType(TextFormField));

  /// Picks [label] out of the searchable select: type the full label, then tap
  /// the option in the overlay — tapping is what fires `onSelected`, and
  /// `onSelected` is the only way a value reaches the screen.
  Future<void> pickProduct(WidgetTester tester, String label) async {
    await tester.enterText(find.descendant(of: productField(), matching: find.byType(TextFormField)), label);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.text(label)).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('productionSave')));
    await tester.pumpAndSettle();
  }

  List<RecordedCall> runsPosted(FullStubAdapter stub) =>
      stub.calls.where((c) => c.method == 'POST' && c.path == '/production-orders').toList();

  group('Add production — the required field says which field', () {
    testWidgets('submitting with no product chosen reds the Product field itself', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      await tapCreate(tester);

      // The message is ON the field, not floating at the bottom of the page
      // naming nothing. This is the whole complaint.
      expect(
        find.descendant(of: productField(), matching: find.text('This field is required.')),
        findsOneWidget,
        reason: 'the error belongs to the Product picker, which is the field that is missing',
      );
      expect(runsPosted(app.stub), isEmpty, reason: 'and nothing was sent');
    });

    testWidgets('the Product field is marked required, so it is identifiable before submitting', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      // `required: true` draws the asterisk through FormFieldWrapper. Without
      // it the only required field on the page looked exactly like the optional
      // ones.
      expect(find.descendant(of: find.byType(RichText), matching: find.text('Product')), findsNothing);
      final labels = tester.widgetList<RichText>(find.byType(RichText)).map((w) => w.text.toPlainText());
      expect(labels, contains('Product *'));
    });

    testWidgets('a typed-but-never-picked product is reported, not silently dropped', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      // Text in the box, but the option was never tapped — so the screen holds
      // no product. This is the other way to reach "I already filled it".
      await tester.enterText(
        find.descendant(of: productField(), matching: find.byType(TextFormField)),
        'Oak Dining',
      );
      await tester.pumpAndSettle();
      await tapCreate(tester);

      expect(find.descendant(of: productField(), matching: find.text('This field is required.')), findsOneWidget);
      expect(runsPosted(app.stub), isEmpty);
    });
  });

  group('Add production — an empty picker is a dead end, not a missing field', () {
    testWidgets('a business with no finished products is told to create one', (tester) async {
      // Every business starts here: no products at all, so nothing to pick, so
      // `_product` can never be set, so the old form said "This field is
      // required." forever.
      final app = apiBackedApp(extraResponses: {
        'GET /products': {
          'success': true,
          'data': const [],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 0}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      expect(
        find.text('No finished products yet. Create one first — a production run needs something to make.'),
        findsOneWidget,
      );
      expect(find.text('Add Products'), findsOneWidget, reason: 'and a way to go and do it');
      expect(
        find.text('This field is required.'),
        findsNothing,
        reason: 'nothing is missing — there is nothing to choose, which is a different problem',
      );
    });

    testWidgets('pressing Create on that screen says the true thing, not "Unable to save"', (tester) async {
      // Found by driving the real app, not by this suite: with no products the
      // picker is REPLACED by the empty state, so there is no Product field for
      // `validate()` to fail on and it passes. `_product!` then threw a null
      // check into the generic `catch (_)`, and the screen answered "Unable to
      // save. Please try again." directly underneath a panel already explaining
      // that a product has to be created first.
      final app = apiBackedApp(extraResponses: {
        'GET /products': {
          'success': true,
          'data': const [],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 0}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      await tapCreate(tester);

      expect(find.text('Unable to save. Please try again.'), findsNothing);
      expect(
        find.text('No finished products yet. Create one first — a production run needs something to make.'),
        findsWidgets,
        reason: 'the reason it cannot be saved is the reason already on screen',
      );
      expect(runsPosted(app.stub), isEmpty);
    });

    testWidgets('raw materials alone are not something to produce', (tester) async {
      // The picker only offers finished goods. A business holding nothing but
      // raw materials has an empty picker for the same reason, and the same
      // thing needs saying.
      final app = apiBackedApp(extraResponses: {
        'GET /products': {
          'success': true,
          'data': [
            {
              'id': 9, 'businessId': 1, 'name': 'Oak Plank', 'productCode': 'RAW-0009',
              'categoryId': 3, 'status': 'active', 'productType': 'raw_material',
              'currentQuantity': 40, 'reservedQuantity': 0, 'unitName': 'Piece',
              'sellingPrice': 0.0, 'purchaseCost': 12.0, 'createdAt': '2026-09-28 20:39:00',
            },
          ],
          'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 1}},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);

      expect(
        find.text('No finished products yet. Create one first — a production run needs something to make.'),
        findsOneWidget,
      );
    });
  });

  group('Add production — the quantity and the assignment', () {
    testWidgets('a quantity of zero reports itself and sends nothing', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);
      await pickProduct(tester, fixtureProductName);

      await tester.enterText(quantityField(), '0');
      await tester.pumpAndSettle();
      await tapCreate(tester);

      // The server's `positiveQuantitySchema` refuses zero. It used to be
      // `int.tryParse(...) ?? 1`, which turned anything unreadable into a batch
      // of one without telling anybody.
      expect(find.text('Enter a quantity greater than zero.'), findsWidgets);
      expect(runsPosted(app.stub), isEmpty);
    });

    testWidgets('the assigned employee actually reaches the request', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);
      await pickProduct(tester, fixtureProductName);

      await tester.tap(find.byKey(const ValueKey('productionEmployee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(fixtureStaffName).last);
      await tester.pumpAndSettle();

      await tapCreate(tester);

      final posted = runsPosted(app.stub);
      expect(posted, hasLength(1));
      expect(
        posted.single.body!['assignedUserId'],
        8552,
        reason: 'the Employee box used to be collected and then left out of the request entirely',
      );
      expect(posted.single.body!['productId'], 5);
      expect(posted.single.body!['quantityPlanned'], 1);
    });

    testWidgets("the server's own refusal is shown, not \"Unable to save\"", (tester) async {
      // The commonest real refusal: a finished product that has no recipe yet.
      // `catch (_) => l10n.unableToSave` threw that sentence away, leaving an
      // operator who had filled the form correctly with no idea that the thing
      // to do was go and add a bill of materials.
      const refusal = '"Oak Dining Table" has no bill of materials, so there is nothing to make it from. '
          'Add one first, or send the materials with the run.';
      final app = apiBackedApp(extraResponses: {
        'POST /production-orders': {
          'success': false,
          'error': {'code': 'VALIDATION_ERROR', 'message': refusal},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);
      await pickProduct(tester, fixtureProductName);

      await tapCreate(tester);

      expect(find.text(refusal), findsOneWidget);
      expect(find.text('Unable to save. Please try again.'), findsNothing);
    });

    testWidgets('a complete run posts once, with the quantity that was typed', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.productionNew);
      await pickProduct(tester, fixtureProductName);

      await tester.enterText(quantityField(), '4');
      await tester.pumpAndSettle();
      await tapCreate(tester);

      final posted = runsPosted(app.stub);
      expect(posted, hasLength(1));
      expect(posted.single.body!['quantityPlanned'], 4);
      // No assignment was made, so none is claimed.
      expect(posted.single.body!.containsKey('assignedUserId'), isFalse);
    });
  });
}
