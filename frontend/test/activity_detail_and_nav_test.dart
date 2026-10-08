// Two asks, together because both are about not making people hunt.
//
//   The activity trail — a row shows four columns because a table has to fit.
//   Opening one gives the rest of the record, and the option to file it as a
//   document.
//
//   The two navigation bars — §8 forbids reaching one destination two ways.
//   Signing out was in BOTH: an icon at the foot of the rail AND the account
//   menu in the header. One of them had to go.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/navigation/app_rail.dart';
import 'package:warehouse_os_app/shared/navigation/app_topbar.dart';
import 'package:warehouse_os_app/shared/navigation/nav_items.dart';

import 'fakes/api_backed_app.dart';

void main() {
  group('an activity row opens the record behind it', () {
    testWidgets('tapping a row shows the fields the table has no space for', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.activityHistory);

      await tester.tap(find.text(fixtureAuditDescription).first);
      await tester.pumpAndSettle();

      expect(find.text('Activity record'), findsOneWidget);
      // The parts that make an entry checkable against anything else, and which
      // the four-column table cannot show.
      expect(find.text('IP address'), findsWidgets);
      expect(find.text('Action'), findsWidgets);
      expect(find.text(fixtureAuditDescription), findsWidgets);
    });

    testWidgets('and offers to file it, asking the server for the document', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.activityHistory);

      await tester.tap(find.text(fixtureAuditDescription).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activitySavePdf')));
      await tester.pumpAndSettle();

      expect(
        app.stub.calls.where((c) => c.method == 'GET' && c.path.endsWith('/pdf') && c.path.startsWith('/audit-logs')),
        isNotEmpty,
        reason: 'the trail is evidence — the document comes from the record, not from this screen',
      );
    });

    testWidgets('a save that cannot happen says why', (tester) async {
      // On the VM `downloadBytes` refuses outright; the browser build is the one
      // that can hand over a file. So this is the failure path, and it has to be
      // spoken rather than swallowed.
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.activityHistory);

      await tester.tap(find.text(fixtureAuditDescription).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activitySavePdf')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the two bars do not carry the same thing twice', () {
    testWidgets('signing out is in the header only, not also at the foot of the rail', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.dashboard);

      expect(find.byType(AppRail), findsOneWidget, reason: 'desktop width, so there is a rail to check');
      expect(
        find.descendant(of: find.byType(AppRail), matching: find.byIcon(Icons.logout)),
        findsNothing,
        reason: 'it lives in the account menu, next to the name of the account being signed out of',
      );
      expect(find.byType(AppTopBar), findsOneWidget);
    });

    testWidgets('the rail keeps the theme toggle, which the header then does not show', (tester) async {
      final app = apiBackedApp();
      addTearDown(app.container.dispose);
      await pumpAppAt(tester, app.container, AppRoutes.dashboard);

      // One surface each: the rail has it because the rail exists.
      final inRail = find.descendant(
        of: find.byType(AppRail),
        matching: find.byIcon(Icons.dark_mode_outlined),
      );
      final inHeader = find.descendant(
        of: find.byType(AppTopBar),
        matching: find.byIcon(Icons.dark_mode_outlined),
      );
      expect(inRail, findsOneWidget);
      expect(inHeader, findsNothing);
    });

    test('no module appears in both bars, for any role', () {
      // By construction rather than by luck: the rail takes exactly what the
      // header did not. Asserted over every business module so a future
      // reordering of `primaryNavRoutes` cannot quietly overlap.
      final split = splitNavItems(businessNavItems);
      final header = split.primary.map((i) => i.route).toSet();
      final rail = split.secondary.map((i) => i.route).toSet();

      expect(header.intersection(rail), isEmpty);
      expect(
        header.union(rail).length,
        businessNavItems.length,
        reason: 'and nothing is dropped on the floor between them',
      );
    });

    test('the same holds for the System Admin area', () {
      final split = splitNavItems(adminNavItems, primaryRoutes: adminPrimaryNavRoutes);
      final header = split.primary.map((i) => i.route).toSet();
      final rail = split.secondary.map((i) => i.route).toSet();

      expect(header.intersection(rail), isEmpty);
      expect(
        rail,
        isEmpty,
        reason: 'the admin area is small enough that every destination fits in the header',
      );
    });
  });
}
