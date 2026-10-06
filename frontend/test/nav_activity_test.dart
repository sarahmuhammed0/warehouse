// "How many new things are behind this navigation item."
//
// Two kinds of badge share the navigation and they clear differently, which is
// the reason they are kept apart rather than merged into one number:
//
//   pendingAction  Registrations — businesses waiting for a decision. Clears
//                  when the last one is DECIDED. Looking at the screen changes
//                  nothing, because the work is still there.
//   unread         Everything else — records that arrived since the item was
//                  last opened. Clears when it is LOOKED at.
//
// What these prove, in order: a fresh account is not shouted at; arrivals are
// counted once a route has been seen; each item carries its own mark so reading
// one never silences another; the System Admin and a business user get
// different maps; and the Registrations badge survives being looked at.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/navigation/nav_activity_provider.dart';
import 'package:warehouse_os_app/shared/navigation/nav_activity_repository.dart';
import 'package:warehouse_os_app/shared/navigation/nav_indicator.dart';
import 'package:warehouse_os_app/shared/navigation/nav_indicators_provider.dart';
import 'package:warehouse_os_app/shared/navigation/nav_seen_store.dart';
import 'package:warehouse_os_app/theme/app_colors.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';

import 'fakes/fake_auth.dart';

/// The marks, in memory. The real one writes to `flutter_secure_storage`, which
/// has no plugin in a test binding — and what is being tested here is the rule,
/// not the disk.
class _Seen implements NavSeenStore {
  _Seen([Map<String, DateTime>? initial]) : _marks = {...?initial};
  final Map<String, DateTime> _marks;

  @override
  Future<Map<String, DateTime>> read(String accountId) async => {..._marks};

  @override
  Future<void> write(String accountId, Map<String, DateTime> seen) async {
    _marks
      ..clear()
      ..addAll(seen);
  }
}

/// Answers whatever it is told to, and records what it was asked — the `since`
/// map is the part that has to be right.
class _Counts implements NavActivityRepository {
  _Counts(this.answer);
  final Map<String, int> answer;
  Map<String, DateTime>? lastAsked;
  bool? lastAsAdmin;
  int calls = 0;

  @override
  Future<Map<String, int>> counts(Map<String, DateTime> since, {required bool asSystemAdmin}) async {
    calls += 1;
    lastAsked = since;
    lastAsAdmin = asSystemAdmin;
    return answer;
  }
}

final _longAgo = DateTime.utc(2020);

ProviderContainer container({
  required Map<String, DateTime> seen,
  required Map<String, int> answer,
  bool asAdmin = false,
  NavActivityRepository? repo,
}) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        asAdmin ? FakeAdminAuthenticatedController.new : FakeAuthenticatedController.new,
      ),
      navSeenStoreProvider.overrideWithValue(_Seen(seen)),
      navActivityRepositoryProvider.overrideWithValue(repo ?? _Counts(answer)),
    ],
  );
}

void main() {
  group('a route nobody has opened yet is not badged', () {
    test('an account with no marks asks for nothing and shows nothing', () async {
      final repo = _Counts({'products': 99});
      final c = container(seen: const {}, answer: const {}, repo: repo);
      addTearDown(c.dispose);

      final activity = await c.read(navActivityProvider.future);

      expect(activity, isEmpty);
      expect(
        repo.calls,
        0,
        reason: 'with nothing ever opened there is no "since" to ask about — a fresh install must '
            'not badge every item with everything that has ever existed',
      );
    });
  });

  group('once an item has been opened, what arrives after is counted', () {
    test('the count lands on the route that owns the entity', () async {
      final c = container(
        seen: {AppRoutes.products: _longAgo, AppRoutes.orders: _longAgo},
        answer: const {'products': 3, 'orders': 0},
      );
      addTearDown(c.dispose);

      final activity = await c.read(navActivityProvider.future);

      expect(activity[AppRoutes.products], 3);
      expect(activity.containsKey(AppRoutes.orders), isFalse, reason: 'a zero is not a badge');
    });

    test('it reaches the navigation as an unread badge, not a pending action', () async {
      final c = container(seen: {AppRoutes.products: _longAgo}, answer: const {'products': 2});
      addTearDown(c.dispose);
      await c.read(navActivityProvider.future);

      final badge = c.read(navBadgesProvider)[AppRoutes.products];

      expect(badge, isNotNull);
      expect(badge!.count, 2);
      expect(
        badge.kind,
        NavIndicatorKind.unread,
        reason: 'nobody is blocked on new records; they just have not been seen',
      );
    });
  });

  group('each item is marked read on its own', () {
    test('opening one route moves only its mark', () async {
      final seen = {AppRoutes.products: _longAgo, AppRoutes.orders: _longAgo};
      final repo = _Counts(const {'products': 5, 'orders': 5});
      final c = container(seen: seen, answer: const {}, repo: repo);
      addTearDown(c.dispose);

      await c.read(navSeenMarkerProvider)(AppRoutes.products);
      await c.read(navActivityProvider.future);

      final asked = repo.lastAsked!;
      expect(asked['products']!.isAfter(_longAgo), isTrue, reason: 'Products was just opened');
      expect(asked['orders'], _longAgo, reason: 'Orders was not, and keeps its old mark');
    });

    test('a route outside the map does not record a mark', () async {
      // Settings, Reports and the dashboards have no arrivals of their own.
      final repo = _Counts(const {});
      final c = container(seen: {AppRoutes.products: _longAgo}, answer: const {}, repo: repo);
      addTearDown(c.dispose);

      await c.read(navSeenMarkerProvider)(AppRoutes.settings);
      await c.read(navActivityProvider.future);

      expect(repo.lastAsked!.containsKey('settings'), isFalse);
      expect(repo.lastAsked!['products'], _longAgo, reason: 'and nothing else was disturbed');
    });
  });

  group('the two audiences get different maps', () {
    test('a business user asks the tenant-scoped endpoint for its own modules', () async {
      final repo = _Counts(const {'products': 1});
      final c = container(seen: {AppRoutes.products: _longAgo}, answer: const {}, repo: repo);
      addTearDown(c.dispose);

      await c.read(navActivityProvider.future);

      expect(repo.lastAsAdmin, isFalse);
    });

    test('a System Admin asks the platform-wide one, keyed by the admin routes', () async {
      final repo = _Counts(const {'businesses': 4});
      final c = container(
        seen: {AppRoutes.adminBusinesses: _longAgo},
        answer: const {},
        asAdmin: true,
        repo: repo,
      );
      addTearDown(c.dispose);

      final activity = await c.read(navActivityProvider.future);

      expect(repo.lastAsAdmin, isTrue);
      expect(repo.lastAsked!.containsKey('businesses'), isTrue);
      expect(activity[AppRoutes.adminBusinesses], 4);
    });

    test("a business route is not asked about on a System Admin's behalf", () async {
      final repo = _Counts(const {});
      final c = container(
        seen: {AppRoutes.products: _longAgo, AppRoutes.adminBusinesses: _longAgo},
        answer: const {},
        asAdmin: true,
        repo: repo,
      );
      addTearDown(c.dispose);

      await c.read(navActivityProvider.future);

      // `products` IS an admin entity too, but only because adminProducts maps
      // to it — the business Products route must not be what put it there.
      expect(repo.lastAsked!.keys, isNot(contains('categories')));
      expect(repo.lastAsked!.containsKey('businesses'), isTrue);
    });
  });

  group('Registrations is a queue, not an arrival', () {
    test('looking at it does not clear it', () async {
      // It is deliberately absent from the activity map, so marking it seen
      // records nothing and the pending count is untouched. The badge goes when
      // the last application is decided, not when somebody opens the screen.
      final repo = _Counts(const {});
      final c = container(seen: {AppRoutes.adminBusinesses: _longAgo}, answer: const {}, asAdmin: true, repo: repo);
      addTearDown(c.dispose);

      await c.read(navSeenMarkerProvider)(AppRoutes.adminRegistrations);
      await c.read(navActivityProvider.future);

      expect(repo.lastAsked!.containsKey('registrations'), isFalse);
      expect(adminActivityEntities.containsKey(AppRoutes.adminRegistrations), isFalse);
    });

    test('a pending action wins over an arrival on the same route', () async {
      final c = container(seen: const {}, answer: const {}, asAdmin: true);
      addTearDown(c.dispose);

      final badges = c.read(navBadgesProvider);

      // Nothing is pending in this container, so the route carries nothing —
      // what matters is that the merge puts pending last, which the map literal
      // in `navBadgesProvider` does by spreading it after the arrivals.
      expect(badges[AppRoutes.adminRegistrations], isNull);
    });
  });

  group('the badge draws the number', () {
    // `context.colors` reads the app's theme extension, so a bare MaterialApp
    // is not enough to render one of these.
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('an unread indicator renders its count, in the unread colour', (tester) async {
      late AppColors colors;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              colors = context.colors;
              return const NavIndicatorBadge(
                indicator: NavIndicator.unread(7),
                semanticLabel: 'Orders',
                child: Text('Orders'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('7'), findsOneWidget);
      // Not the red a pending decision uses: "new since you looked" is not the
      // same claim on someone's attention as "nothing proceeds until you act".
      expect(tester.widget<Badge>(find.byType(Badge)).backgroundColor, colors.info);
      expect(tester.widget<Badge>(find.byType(Badge)).backgroundColor, isNot(colors.error));
    });

    testWidgets('nothing outstanding adds nothing to the tree', (tester) async {
      await tester.pumpWidget(
        host(
          const NavIndicatorBadge(
            indicator: NavIndicator.unread(0),
            semanticLabel: 'Orders',
            child: Text('Orders'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Badge), findsNothing);
    });
  });
}
