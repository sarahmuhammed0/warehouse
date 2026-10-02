// What the screens DO, not just what they show.
//
// `all_screens_test.dart` proves every route renders the server's data.
// This drives the actions on them — tapping the control a user taps — and
// asserts the request that reached the server. A screen that renders perfectly
// and sends the wrong body, or nothing at all, passes that sweep and fails
// here.
//
// Each test names the action in the user's terms, because that is the thing
// being verified: "disabling a member of staff ends their access", not
// "PATCH /users/:id is called".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  /// Opens a Settings section by its icon. Its LABEL cannot be used: the
  /// business section is labelled the same as the page title and the sidebar
  /// entry, so a text tap lands on whichever came first.
  Future<void> openSettingsSection(WidgetTester tester, IconData icon) async {
    final finder = find.byIcon(icon).first;
    expect(finder, findsOneWidget, reason: 'no settings section with that icon');
    await tester.ensureVisible(finder);
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Taps the first widget whose text contains [text].
  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.textContaining(text, findRichText: true).first;
    expect(finder, findsOneWidget, reason: 'nothing on screen to tap containing "$text"');
    await tester.ensureVisible(finder);
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Settings writes through as you type, behind a 600ms debounce — so a test
  /// has to wait it out before the request exists to assert on.
  Future<void> settleSettingsDebounce(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  List<RecordedCall> callsTo(FullStubAdapter stub, String method, String path) =>
      stub.calls.where((c) => c.method == method && c.path == path).toList();

  group('Settings', () {
    testWidgets('opening the Business section shows the business the server returned', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.settings);

      // The section list uses the business-settings label for its own entry.
      await openSettingsSection(tester, Icons.business_outlined);

      final field = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((w) => w.controller.text)
          .toList();
      expect(
        field,
        contains(fixtureBusinessName),
        reason: 'the name field still holds the default, so the loaded value never reached it',
      );
    });

    testWidgets('renaming the business sends only the name, to /business', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'PATCH /business': {'success': true, 'data': {'id': 1, 'name': 'Karwan Furniture Co'}},
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.settings);
      await openSettingsSection(tester, Icons.business_outlined);

      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Karwan Furniture Co');
      await settleSettingsDebounce(tester);

      final patches = callsTo(app.stub, 'PATCH', '/business');
      expect(patches, hasLength(1), reason: 'one write for one edit, not one per keystroke');
      expect(patches.single.body!['name'], 'Karwan Furniture Co');
      expect(
        patches.single.body!.containsKey('currency'),
        isFalse,
        reason: 'the currency did not change, so it is not sent',
      );
    });

    testWidgets('a custom field can be added and removed', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'POST /custom-fields': {'success': true, 'data': {'id': 9}},
        'DELETE /custom-fields/3': {'success': true, 'data': {'id': 3, 'deleted': true}},
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.settings);
      await openSettingsSection(tester, Icons.tune);

      expect(find.textContaining(fixtureCustomFieldLabel), findsWidgets, reason: 'the server\'s field should be listed');

      await tester.enterText(find.byType(TextField).last, 'Fabric type');
      await tapText(tester, 'Add');

      final created = callsTo(app.stub, 'POST', '/custom-fields').single;
      expect(created.body!['label'], 'Fabric type');
      expect(created.body!['fieldKey'], 'fabric_type', reason: 'a stable key is derived, not left to the server');

      await tester.tap(find.byIcon(Icons.close).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(callsTo(app.stub, 'DELETE', '/custom-fields/3'), hasLength(1));
    });

    testWidgets('the backup section shows the server\'s record and never claims success', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'POST /admin/backups': {
          'success': true,
          'data': {'id': 2, 'status': 'pending', 'fileProduced': false, 'note': 'Recorded as requested. No file has been written.'},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.settings);
      await openSettingsSection(tester, Icons.backup_outlined);

      // The fixture's one pending row, with the reason it produced nothing.
      expect(find.textContaining('No configured backup target'), findsWidgets);

      await tapText(tester, 'Backup now');

      // The confirmation's button carries the same words as the one that opened
      // it, so it has to be found INSIDE the dialog — `.first` lands back on
      // the page's button and the request never happens.
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Backup now'),
      );
      expect(confirm, findsWidgets, reason: 'the confirmation dialog should be open');
      await tester.tap(confirm.last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(callsTo(app.stub, 'POST', '/admin/backups'), hasLength(1));
      expect(
        find.textContaining('No file has been written'),
        findsWidgets,
        reason: 'the server\'s own answer is shown — never "Backup complete"',
      );
    });

    testWidgets('switching off a payment method sends that one key', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'PATCH /settings': {'success': true, 'data': {'values': <String, dynamic>{}}},
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.settings);
      await openSettingsSection(tester, Icons.point_of_sale_outlined);

      // Cash is on in the fixture; untick it.
      await tapText(tester, 'Cash');
      await settleSettingsDebounce(tester);

      final patch = callsTo(app.stub, 'PATCH', '/settings').single;
      final values = patch.body!['values'] as Map;
      expect(values.keys, ['payments.cash_enabled']);
      expect(values['payments.cash_enabled'], isFalse);
    });
  });

  group('Staff and roles', () {
    testWidgets('the staff list shows the server\'s people', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.employees);

      expect(find.textContaining(fixtureStaffName), findsWidgets);
      expect(find.textContaining('Warehouse Manager'), findsWidgets, reason: 'the role name, not just the id');
    });

    testWidgets('ticking a permission saves the whole set by PUT', (tester) async {
      final app = apiBackedApp(extraResponses: {
        'PUT /roles/11/permissions': {
          'success': true,
          'data': {'id': 11, 'name': 'Business Owner/Admin', 'isSystemRole': true, 'permissions': ['products.view', 'users.view', 'orders.view']},
        },
      });
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.roles);

      // The matrix is checkboxes over module x action. Tick the first unticked.
      final boxes = find.byType(Checkbox);
      expect(boxes, findsWidgets, reason: 'the permission matrix should be on screen');

      var tapped = false;
      for (final element in boxes.evaluate()) {
        final box = element.widget as Checkbox;
        if (box.value == false && box.onChanged != null) {
          await tester.ensureVisible(find.byWidget(box));
          await tester.tap(find.byWidget(box), warnIfMissed: false);
          await tester.pumpAndSettle();
          tapped = true;
          break;
        }
      }
      expect(tapped, isTrue, reason: 'no editable unticked permission found to tick');

      final puts = app.stub.calls.where((c) => c.method == 'PUT' && c.path.startsWith('/roles/')).toList();
      expect(puts, hasLength(1), reason: 'a grid saves as one whole set, not per box');
      expect(puts.single.body!['permissions'], isA<List<dynamic>>());
    });

    testWidgets('selecting a different role shows that role\'s grants', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.roles);

      await tapText(tester, 'Warehouse Manager');

      expect(
        find.textContaining('Warehouse Manager —'),
        findsWidgets,
        reason: 'the matrix heading should follow the selected role',
      );
    });
  });

  group('Activity history', () {
    testWidgets('the trail shows what the server recorded', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.activityHistory);

      expect(find.textContaining(fixtureAuditDescription), findsWidgets);
      expect(find.textContaining(fixtureStaffName), findsWidgets, reason: 'who did it');
    });
  });

  group('Transfers and variants', () {
    testWidgets('the inventory screen lists §11 transfer documents, including pending ones', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.inventory);

      // Transfers are a tab within Inventory rather than a route of their own.
      await tapText(tester, 'Transfer');

      expect(
        find.textContaining(fixtureTransferNumber),
        findsWidgets,
        reason: 'a document number — the ledger rows this replaced had none',
      );
    });

    testWidgets('a product\'s variants come from the server', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/products/5');

      expect(find.textContaining('Finish: White'), findsWidgets);
      expect(callsTo(app.stub, 'GET', '/products/5/variants'), isNotEmpty);
    });
  });

  group('Documents', () {
    testWidgets('Download PDF asks the server to render the invoice', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.documents);

      await tapText(tester, 'Download PDF');

      expect(
        callsTo(app.stub, 'GET', '/orders/21/pdf'),
        hasLength(1),
        reason: 'the file is rendered by the server from the stored document',
      );
    });
  });

  group('System Admin', () {
    testWidgets('editing a business sends the whole profile by PUT', (tester) async {
      final app = apiBackedApp(
        asAdmin: true,
        extraResponses: {
          'PUT /admin/businesses/1': {
            'success': true,
            'data': {'id': 1, 'name': 'Karwan Furniture Group', 'businessType': 'furniture_factory', 'phone': '+9647500000003', 'status': 'active', 'createdAt': '2026-09-28 20:39:24'},
          },
        },
      );
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, '/admin/businesses/1/edit');

      await tester.enterText(find.byType(TextField).first, 'Karwan Furniture Group');
      await tapText(tester, 'Save');

      final put = callsTo(app.stub, 'PUT', '/admin/businesses/1').single;
      expect(put.body!['name'], 'Karwan Furniture Group');
      expect(
        put.body!['businessType'],
        'furniture_factory',
        reason: 'the wire key, not the label the dropdown displays',
      );
    });

    testWidgets('the business type reads as a label, not a database key', (tester) async {
      final app = apiBackedApp(asAdmin: true);
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.adminBusinesses);

      expect(find.textContaining('Furniture Factory'), findsWidgets);
      expect(
        find.textContaining('furniture_factory'),
        findsNothing,
        reason: 'the operator should never be shown the enum value',
      );
    });

    testWidgets('the platform overview counts the businesses the server has', (tester) async {
      final app = apiBackedApp(asAdmin: true);
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.adminEmployees);

      // Drilled down through the admin endpoint for the business the server
      // returned — not for a hardcoded demo id, which is what used to happen.
      expect(callsTo(app.stub, 'GET', '/admin/businesses/1/users'), isNotEmpty);
      expect(
        app.stub.calls.where((c) => c.path.contains('biz-')),
        isEmpty,
        reason: 'no demo business id may be asked for in backend mode',
      );
    });
  });
}
