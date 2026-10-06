// The red dot that tells someone there is something new to look at.
//
// There are two of them, for two different audiences, and they are easy to
// confuse — so this names both:
//
//   Business user → the bell in the header, badged with the number of UNREAD
//                   notifications (§29/§31: low stock, out of stock, a new
//                   order, a run finishing).
//   System Admin  → the Registrations navigation item, badged with the number
//                   of businesses waiting for a decision. Covered by
//                   `nav_indicators_test.dart`; a System Admin belongs to no
//                   business, so the bell has nothing to say to them.
//
// The admin half had tests. The bell's badge only had one at the repository
// level — `unreadCount()` returning the right number — which proves the count is
// fetched and proves nothing about whether a dot is ever drawn. These drive the
// real header, through the real app, and assert on what is actually on screen:
// that the dot appears while something is unread, carries the count, and clears
// itself when everything has been read.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/features/notifications/data/notification_providers.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';

import 'fakes/fake_auth.dart';

void main() {
  ProviderContainer businessContainer() =>
      ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)]);

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
    await tester.pumpAndSettle();
  }

  /// The bell's badge specifically — `Badge` is a Material widget other things
  /// could use, so this is anchored to the notification icon rather than to the
  /// first `Badge` in the tree.
  Finder bellBadge() => find.ancestor(
    of: find.byIcon(Icons.notifications_outlined),
    matching: find.byType(Badge),
  );

  group('the bell carries a dot while something is unread', () {
    testWidgets('the badge is shown, and its number is the unread count', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);

      final unread = container.read(unreadNotificationCountProvider);
      expect(unread, greaterThan(0), reason: 'the demo data must raise something, or this proves nothing');

      expect(bellBadge(), findsOneWidget);
      final badge = tester.widget<Badge>(bellBadge());
      expect(badge.isLabelVisible, isTrue, reason: 'something is unread, so the dot must be visible');
      expect(
        find.descendant(of: bellBadge(), matching: find.text('$unread')),
        findsOneWidget,
        reason: 'the badge must show the real count, not a hardcoded dot',
      );
    });

    testWidgets('reading everything clears it', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      expect(tester.widget<Badge>(bellBadge()).isLabelVisible, isTrue);

      await container.read(notificationsProvider.notifier).markAllRead();
      await tester.pumpAndSettle();

      expect(container.read(unreadNotificationCountProvider), 0);
      expect(
        tester.widget<Badge>(bellBadge()).isLabelVisible,
        isFalse,
        reason: 'nothing is unread any more, so the dot must go — a dot that never clears is noise',
      );
    });

    testWidgets('reading one of them takes the count down by one', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);

      final before = container.read(unreadNotificationCountProvider);
      final first = container.read(notificationsProvider).firstWhere((n) => n.isUnread);
      await container.read(notificationsProvider.notifier).markRead(first.id);
      await tester.pumpAndSettle();

      expect(container.read(unreadNotificationCountProvider), before - 1);
      expect(
        find.descendant(of: bellBadge(), matching: find.text('${before - 1}')),
        findsOneWidget,
        reason: 'the number on screen has to follow the list, not a snapshot taken once',
      );
    });

    testWidgets('the dot survives moving between screens', (tester) async {
      // The bell is drawn by the header on every screen, so a badge built from a
      // provider read once at startup would quietly go stale after navigation.
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      final unread = container.read(unreadNotificationCountProvider);

      await tester.tap(find.text('Products').first);
      await tester.pumpAndSettle();

      expect(bellBadge(), findsOneWidget);
      expect(find.descendant(of: bellBadge(), matching: find.text('$unread')), findsOneWidget);
    });
  });
}
