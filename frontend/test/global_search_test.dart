// Reported from production: the global search "doesn't actually work" — a
// screen headed `Search: ""` listing every product in the business.
//
// Four separate faults produced that:
//
//   1. The compact header carries a search BUTTON, not a field, and it
//      navigated to the results screen with no query — which then had nowhere
//      to type one. A dead end.
//   2. An empty query was passed straight to the repositories. `buildListQuery`
//      omits the parameter when it is blank, so every unfiltered row came back
//      and was presented as a match.
//   3. The four module lookups ran one after another, and a single refusal
//      threw out of the first await. The builder only checked `!hasData`, so
//      the screen span forever. An Accountant has no `products.view` BY DESIGN,
//      so searching as anyone but an owner hung — this is the "on every user
//      account" half of the report.
//   4. Nothing ever checked `snapshot.hasError`, so any failure was an endless
//      spinner rather than a message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  Finder searchInput() => find.descendant(
    of: find.byKey(const ValueKey('searchInput')),
    matching: find.byType(TextField),
  );

  List<RecordedCall> listCalls(FullStubAdapter stub, String path) =>
      stub.calls.where((c) => c.method == 'GET' && c.path == path).toList();

  group('an empty query is not a search', () {
    testWidgets('arriving with no query offers the field and lists nothing', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=');

      // The whole report in one assertion: no product was presented as a match.
      expect(
        find.text(fixtureProductName),
        findsNothing,
        reason: 'nothing was searched for, so nothing can be a result',
      );
      expect(searchInput(), findsOneWidget, reason: 'and there is now somewhere to type');
      expect(
        find.text('Type a product, customer, supplier or order number to search for.'),
        findsOneWidget,
      );
    });

    testWidgets('it does not even ask the API', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=');

      // The dashboard fetches products on the way through, so "was /products
      // called" proves nothing. And a BLANK term adds no `search=` to the query
      // at all — which is exactly the bug: the request goes out unfiltered and
      // everything comes back. So the tell is the search's own page size, which
      // nothing else on the way here uses.
      // Anchored, not `contains`: the notification feed asks for pageSize=50,
      // which a substring match happily accepts.
      final searchSized = RegExp(r'pageSize=5(&|$)');
      expect(
        app.stub.calls.where((c) => searchSized.hasMatch(c.fullPath)),
        isEmpty,
        reason: 'nothing was typed, so no lookup should have been made at all',
      );
    });
  });

  group('a real query searches', () {
    testWidgets('typing and submitting puts the term on every module', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=');

      await tester.enterText(searchInput(), 'Oak');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      for (final path in ['/products', '/customers', '/suppliers', '/orders']) {
        final calls = listCalls(app.stub, path);
        expect(calls, isNotEmpty, reason: '$path was not searched');
        expect(
          calls.last.fullPath,
          contains('search=Oak'),
          reason: '$path was asked without the term, so it would answer with everything',
        );
      }
    });

    testWidgets('the query lands in the URL, so a search can be shared and reloaded', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=');

      await tester.enterText(searchInput(), 'Oak');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Search: "Oak"'), findsOneWidget);
    });

    testWidgets('results are grouped, and a match is shown', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=Oak');

      expect(find.text(fixtureProductName), findsWidgets);
    });
  });

  group('a role that cannot open a module still gets a search', () {
    testWidgets('a refused module is skipped, not fatal', (tester) async {
      // What an Accountant meets: `products.view` refused. The other three
      // modules must still answer, and the screen must not spin forever.
      final app = apiBackedApp(extraResponses: {
        'GET /products': {
          'success': false,
          'error': {'code': 'FORBIDDEN', 'message': 'You do not have permission to do that.'},
        },
      });
      addTearDown(app.container.dispose);
      // `settle: false` — refusing /products also breaks the dashboard the app
      // passes through, and its spinner would time out `pumpAndSettle` before
      // this screen was ever reached.
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=Ahmed', settle: false);

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the endless spinner was the bug — searching as an Accountant simply hung',
      );
      expect(find.text(fixtureCustomerName), findsWidgets, reason: 'what the role CAN see still comes back');
      expect(find.text('Some modules could not be searched with your permissions.'), findsOneWidget);

      // Let the dashboard's own retry timer fire. Without `pumpAndSettle` to
      // drain it, the binding asserts on a timer outliving the tree.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('if every module refuses, that is reported rather than called "no results"', (tester) async {
      final refusal = {
        'success': false,
        'error': {'code': 'FORBIDDEN', 'message': 'You do not have permission to do that.'},
      };
      final app = apiBackedApp(extraResponses: {
        'GET /products': refusal,
        'GET /customers': refusal,
        'GET /suppliers': refusal,
        'GET /orders': refusal,
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '${AppRoutes.search}?q=Oak', settle: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Nothing here yet'),
        findsNothing,
        reason: 'nothing was searched successfully, so "no results" would be a lie',
      );
      expect(find.text('Unable to load this list. Please try again.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
