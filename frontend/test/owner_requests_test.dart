// Five changes asked for together, each proved here.
//
//   1. Add Sale — an "Add more" button opening a scrollable, multi-select
//      product list OVER the form, with an Add button at the bottom.
//   2. Add Sale — the Paid field removed.
//   3. A record opened from a history list can be saved as a PDF.
//   5. Adding a user takes a password alongside name, phone and role.
//
// (4, the document's own layout, is a server concern and is covered by
// `backend/tests/unit/invoicePdf.test.js` and the §28 integration tests.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';
import 'package:warehouse_os_app/features/employees/presentation/employee_form_dialog.dart';
import 'package:warehouse_os_app/features/employees/data/employee_models.dart';

import 'fakes/api_backed_app.dart';

/// A catalogue worth multi-selecting from — the shared fixture holds one
/// product, and "add several at once" cannot be shown with one.
Map<String, Map<String, dynamic>> catalogue() {
  Map<String, dynamic> product(int id, String name, String code) => {
    'id': id,
    'businessId': 1,
    'name': name,
    'productCode': code,
    'sku': code,
    'categoryId': 3,
    'status': 'active',
    'productType': 'finished_good',
    'currentQuantity': 10,
    'reservedQuantity': 0,
    'unitName': 'Piece',
    'sellingPrice': 25.0,
    'purchaseCost': 10.0,
    'createdAt': '2026-09-28 20:39:00',
  };
  return {
    'GET /products': {
      'success': true,
      'data': [
        product(5, 'Oak Dining Table', 'TBL-1'),
        product(6, 'Walnut Shelf', 'SHF-2'),
        product(7, 'Pine Stool', 'STL-3'),
      ],
      'meta': {'pagination': {'page': 1, 'pageSize': 20, 'total': 3}},
    },
  };
}

void main() {
  group('1. Add Sale — several products at once, over the form', () {
    testWidgets('the Add more button opens the picker without leaving the page', (tester) async {
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('productPickerList')), findsOneWidget);
      expect(
        find.text('Add Sales'),
        findsWidgets,
        reason: 'the sale form is still underneath — the picker is a dialog, not a trip to another screen',
      );
    });

    testWidgets('ticking several and pressing Add puts them all on the sale', (tester) async {
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick:6')));
      await tester.tap(find.byKey(const ValueKey('pick:7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('productPickerAdd')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('productPickerList')), findsNothing, reason: 'the dialog closed');
      expect(find.text('Walnut Shelf'), findsWidgets);
      expect(find.text('Pine Stool'), findsWidgets);
    });

    testWidgets('Add is refused while nothing is ticked', (tester) async {
      // A button that closes the dialog and changes nothing reads as a failure.
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();

      final add = tester.widget<Widget>(find.byKey(const ValueKey('productPickerAdd')));
      expect((add as dynamic).onPressed, isNull);
    });

    testWidgets('a product already on the sale is shown ticked and cannot be added twice', (tester) async {
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      // Put one on the sale through the picker, then reopen it.
      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick:6')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('productPickerAdd')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('pick:6')));
      expect(tile.value, isTrue, reason: 'it is on the sale');
      expect(tile.onChanged, isNull, reason: 'and adding it again would mean a second line, not more of it');
    });

    testWidgets('the list filters, so a long catalogue stays usable', (tester) async {
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      await tester.tap(find.byKey(const ValueKey('addMoreProducts')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('productPickerSearch')), matching: find.byType(TextFormField)),
        'Walnut',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pick:6')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick:7')), findsNothing);
    });
  });

  group('2. Add Sale — the Paid field is gone', () {
    testWidgets('neither Paid nor the Remaining row it fed is on the form', (tester) async {
      final app = apiBackedApp(extraResponses: catalogue());
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.saleNew);

      expect(find.text('Paid amount'), findsNothing);
      // Remaining was derived from Paid; with nothing paid at creation it could
      // only ever repeat the grand total.
      expect(find.text('Remaining amount'), findsNothing);
      // The rest of the totals are untouched.
      expect(find.text('Grand total'), findsWidgets);
    });
  });

  group('3. A record opened from history can be filed', () {
    testWidgets('Save as PDF asks the server for the document', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/orders/21');

      final save = find.byKey(const ValueKey('orderSavePdf'));
      expect(save, findsOneWidget, reason: 'the action has to be on the record you opened');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        app.stub.calls.where((c) => c.method == 'GET' && c.path == '/orders/21/pdf'),
        isNotEmpty,
        reason: 'the file is rendered by the server from what was stored, not drawn from this screen',
      );
    });

    testWidgets('a save that cannot happen says so rather than doing nothing', (tester) async {
      // `flutter test` runs on the VM, where `downloadBytes` refuses outright —
      // the browser build is the one that can hand over a file. Which makes this
      // the failure path, and it must be spoken aloud.
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/orders/21');

      await tester.ensureVisible(find.byKey(const ValueKey('orderSavePdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('orderSavePdf')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('5. Adding a user takes a password', () {
    Widget host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('the field is there when creating', (tester) async {
      await tester.pumpWidget(host(const EmployeeFormDialog()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('employeePassword')), findsOneWidget);
    });

    testWidgets('it is required, and short ones are refused before the round trip', (tester) async {
      await tester.pumpWidget(host(const EmployeeFormDialog()));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byKey(const ValueKey('employeePassword')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, 'short');
      await tester.pumpAndSettle();

      // Eight is the server's own minimum; being told here beats being told
      // after a failed save.
      expect(find.text('Password must be at least 8 characters.'), findsOneWidget);
    });

    testWidgets('editing an existing user does not offer it', (tester) async {
      // Changing a password is its own endpoint. Offering it on a details form
      // would make renaming somebody look like resetting them.
      await tester.pumpWidget(
        host(
          EmployeeFormDialog(
            editing: Employee(
              id: '1',
              businessId: '1',
              name: 'Dara Salih',
              phone: '+9647500000011',
              roleId: 'role-warehouse',
              roleName: 'Warehouse Manager',
              status: EmployeeStatus.active,
              createdAt: DateTime(2026),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('employeePassword')), findsNothing);
    });
  });
}
