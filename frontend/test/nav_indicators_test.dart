// Pending-action indicators on the navigation.
//
// The property that matters is not "a badge can be drawn" — it is that the
// badge is DERIVED, so it appears only while something is outstanding and
// clears itself when the work is done. A badge somebody has to remember to
// clear is worse than none: it trains people to ignore it.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/features/admin/data/registration_queue_repository.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/navigation/nav_indicator.dart';
import 'package:warehouse_os_app/shared/navigation/nav_indicators_provider.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';

import 'fakes/fake_auth.dart';

BusinessRegistration _registration(String id) => BusinessRegistration(
  id: id,
  name: "Sara's place $id",
  businessType: 'general_factory',
  phone: '+9647500335775',
  ownerName: 'sarah muhammed ahmed',
  ownerPhone: '+9647500335775',
  status: 'pending',
  createdAt: DateTime(2026, 10, 6),
);

ProviderContainer _containerWith(List<BusinessRegistration> pending) {
  final container = ProviderContainer(
    overrides: [
      // A System Admin session: the provider is deliberately inert otherwise,
      // so that a business user never fires an admin-only request.
      authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new),
      pendingRegistrationsProvider.overrideWith((ref) async => pending),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<Map<String, NavIndicator>> _indicators(List<BusinessRegistration> pending) async {
  final container = _containerWith(pending);
  // The provider is async underneath; let it resolve before reading the map.
  await container.read(pendingRegistrationsProvider.future);
  return container.read(navIndicatorsProvider);
}

void main() {
  group('The indicator is derived from real pending work', () {
    test('one pending registration gives Registrations a count of 1', () async {
      final indicators = await _indicators([_registration('1')]);

      final badge = indicators[AppRoutes.adminRegistrations];
      expect(badge, isNotNull);
      expect(badge!.count, 1);
      expect(badge.kind, NavIndicatorKind.pendingAction);
    });

    test('three pending registrations count three', () async {
      final indicators = await _indicators([
        _registration('1'),
        _registration('2'),
        _registration('3'),
      ]);

      expect(indicators[AppRoutes.adminRegistrations]!.count, 3);
    });

    test('deciding the last one clears the badge', () async {
      // The state after approving or rejecting: the screen invalidates
      // pendingRegistrationsProvider, it refetches, and the queue is empty.
      // Nothing clears the badge explicitly — there is nothing to forget.
      final indicators = await _indicators([]);

      expect(
        indicators[AppRoutes.adminRegistrations],
        isNull,
        reason: 'an empty queue must leave no badge behind',
      );
    });

    test('nothing is shown while the count is still loading', () {
      // Read before the future resolves. A number that is not known yet must
      // not be drawn, and a slow request must not flash a badge on and off.
      final container = _containerWith([_registration('1')]);
      expect(container.read(navIndicatorsProvider), isEmpty);
    });
  });

  group('Only states that actually exist are badged', () {
    test('no indicator is invented for the read-only admin screens', () async {
      // §57 gives the platform operator oversight, not operation: there is no
      // admin action on another business's staff, stock or orders, so none of
      // these can ever be pending FOR THE ADMIN. Badging them would send
      // someone to a screen with no button on it.
      final indicators = await _indicators([_registration('1')]);

      for (final route in [
        AppRoutes.adminEmployees,
        AppRoutes.adminProducts,
        AppRoutes.adminOrders,
        AppRoutes.adminSales,
        AppRoutes.adminDashboard,
      ]) {
        expect(indicators[route], isNull, reason: '$route has no admin-actionable state');
      }
    });

    test('Businesses is not badged for the same queue as Registrations', () async {
      // A business at status `pending` IS a pending registration. Badging both
      // would count one queue twice and point at the screen that cannot act.
      final indicators = await _indicators([_registration('1'), _registration('2')]);

      expect(indicators[AppRoutes.adminBusinesses], isNull);
      expect(indicators[AppRoutes.adminRegistrations]!.count, 2);
    });
  });

  group('It renders, in both themes', () {
    Widget host(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

    for (final (name, theme) in [('light', AppTheme.light()), ('dark', AppTheme.dark())]) {
      testWidgets('$name mode draws the count', (tester) async {
        await tester.pumpWidget(
          host(
            theme,
            const NavIndicatorBadge(
              indicator: NavIndicator.pendingAction(3),
              semanticLabel: 'Registrations',
              child: Text('Registrations'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('3'), findsOneWidget);
      });
    }

    testWidgets('a large count is capped rather than distorting the item', (tester) async {
      await tester.pumpWidget(
        host(
          AppTheme.light(),
          const NavIndicatorBadge(
            indicator: NavIndicator.pendingAction(42),
            child: Text('Registrations'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('9+'), findsOneWidget);
      expect(find.text('42'), findsNothing);
    });

    testWidgets('nothing outstanding adds nothing to the tree', (tester) async {
      await tester.pumpWidget(
        host(
          AppTheme.light(),
          const NavIndicatorBadge(
            indicator: NavIndicator.pendingAction(0),
            child: Text('Registrations'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsNothing, reason: 'the quiet state costs nothing');
      expect(find.text('Registrations'), findsOneWidget);
    });

    testWidgets('the rail variant shows a dot with no number', (tester) async {
      await tester.pumpWidget(
        host(
          AppTheme.light(),
          const NavIndicatorBadge(
            indicator: NavIndicator.pendingAction(4),
            showCount: false,
            child: Icon(Icons.how_to_reg_outlined),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('4'), findsNothing, reason: 'a number inside a 20px icon is unreadable');
    });

    testWidgets('a screen reader is told what is waiting', (tester) async {
      await tester.pumpWidget(
        host(
          AppTheme.light(),
          const NavIndicatorBadge(
            indicator: NavIndicator.pendingAction(2),
            semanticLabel: 'Registrations',
            child: Text('Registrations'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Registrations, 2 waiting for a decision'),
        findsOneWidget,
      );
    });
  });
}
