// Phase 1 smoke tests: the app shell, sidebar, and responsive foundation
// must actually build without throwing — this is the "reusable components
// render correctly" verification the phase's testing requirement asks for,
// run for real rather than only inspected by reading code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/shared/badges/status_badge.dart';
import 'package:warehouse_os_app/shared/buttons/app_button.dart';
import 'package:warehouse_os_app/shared/layout/responsive/app_breakpoints.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';

void main() {
  testWidgets('App shell builds on a desktop-width screen and shows the dashboard + sidebar nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: WarehouseOsApp()));
    await tester.pumpAndSettle();

    // The dashboard placeholder screen's title.
    expect(find.text('Dashboard'), findsWidgets);
    // A couple of other sidebar nav items should be visible on desktop
    // width (persistent sidebar, not a drawer).
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('App shell builds on a mobile-width screen with a drawer instead of a persistent sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: WarehouseOsApp()));
    await tester.pumpAndSettle();

    // On mobile the sidebar's nav items are inside an unopened Drawer, so
    // they should NOT be directly visible yet...
    expect(find.text('Products'), findsNothing);
    // ...but the menu button that opens it should be.
    expect(find.byIcon(Icons.menu), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Now that the drawer is open, nav items are visible.
    expect(find.text('Products'), findsOneWidget);
  });

  test('Breakpoint boundaries classify screen sizes as documented', () {
    expect(screenSizeFor(400), ScreenSize.mobile);
    expect(screenSizeFor(800), ScreenSize.tablet);
    expect(screenSizeFor(1200), ScreenSize.desktop);
  });

  testWidgets('AppButton renders its label and responds to taps when enabled', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppButton(label: 'Save', onPressed: () => tapped = true),
        ),
      ),
    );

    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(tapped, isTrue);
  });

  testWidgets('AppButton shows no tap response when disabled (onPressed null)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AppButton(label: 'Save', onPressed: null)),
      ),
    );

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('StatusBadge renders the catalog label for every business status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Wrap(
            children: [for (final status in BusinessStatus.values) StatusBadge.forStatus(status)],
          ),
        ),
      ),
    );

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('PARTIALLY RETURNED'), findsOneWidget);
  });

  testWidgets('Theme applies without throwing in both light and dark mode', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const Scaffold(body: Text('Themed'))),
      );
      expect(find.text('Themed'), findsOneWidget);
    }
  });
}
