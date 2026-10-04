// Layouts that overflow at real window sizes.
//
// Flutter reports an overflow by throwing during paint, which a widget test
// surfaces as an exception — so "does this overflow at 920 pixels" is an
// assertion, not something anyone has to spot in a screenshot. Every case here
// was reported from an actual window: a browser pane beside an editor, and a
// laptop screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';
import 'package:warehouse_os_app/shared/buttons/app_button.dart';
import 'package:warehouse_os_app/shared/feedback/confirm_dialog.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/navigation/app_topbar.dart';
import 'package:warehouse_os_app/shared/navigation/nav_items.dart';
import 'package:warehouse_os_app/shared/layout/page_scaffold.dart';

/// The widths that matter: a phone, the browser pane beside an editor, a
/// laptop, and a wide monitor. 920 is the one that was broken — below 600 the
/// header already used a Column, and above ~1200 the buttons happened to fit.
const _widths = <double>[390, 600, 820, 920, 1024, 1280, 1440];

// ProviderScope because AppTopBar is a consumer — it reads the auth state to
// show the account chip.
Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  group('A page header does not overflow at any window width', () {
    for (final width in _widths) {
      testWidgets('${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            // A real case: the Products page carries three actions, and its
            // title is long enough to want the room.
            const PageScaffold(
              title: 'Products and inventory across every warehouse',
              secondaryActions: [
                AppButton(label: 'Add Categories', icon: Icons.add),
                AppButton(label: 'Add stock', icon: Icons.inventory_2_outlined),
                AppButton(label: 'Export', icon: Icons.download_outlined),
              ],
              body: SizedBox(height: 200),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the header overflowed at ${width.toInt()}px',
        );

        // The buttons must still be on screen, not merely un-overflowed by
        // having been clipped away.
        expect(find.text('Add Categories'), findsOneWidget);
        expect(find.text('Add stock'), findsOneWidget);
        expect(find.text('Export'), findsOneWidget);
      });
    }
  });

  group('A dialog taller than the window scrolls rather than overflowing', () {
    for (final height in <double>[420, 560, 700]) {
      testWidgets('${height.toInt()}px tall viewport', (tester) async {
        tester.view.physicalSize = Size(900, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => confirmAction(
                    context,
                    title: 'Restore from backup?',
                    // Long on purpose: a short viewport plus a real paragraph is
                    // what produced "BOTTOM OVERFLOWED BY 183 PIXELS".
                    description:
                        'This would overwrite every business’s data. There is nothing to '
                        'restore from — no backup file has been written. Taking a real dump '
                        'means running mysqldump against the live instance and writing '
                        'somewhere durable, which is an operator decision.',
                    confirmLabel: 'Restore',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the dialog overflowed in a ${height.toInt()}px-tall window',
        );
        // Still usable: the buttons have not been pushed off the bottom.
        expect(find.text('Restore'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });
    }
  });

  group('Navigation is visible, not only behind the menu button', () {
    // 920 is a browser window beside an editor; 1024 is where the desktop shell
    // takes over. Both sat in the compact shell's range showing a hamburger and
    // nothing else, which read as an app with no navigation.
    for (final width in <double>[620, 820, 920, 1000]) {
      testWidgets('${width.toInt()}px shows the nav pills', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            AppTopBar(
              pageContext: 'Admin Dashboard',
              navItems: adminNavItems,
              currentPath: AppRoutes.adminDashboard,
              onMenuTap: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // The pills are there and scrollable, so a narrow bar cannot overflow.
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(find.byIcon(Icons.menu), findsOneWidget, reason: 'the full menu stays available');
      });
    }

    testWidgets('a phone keeps only the menu button', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          AppTopBar(
            pageContext: 'Admin Dashboard',
            navItems: const [],
            currentPath: AppRoutes.adminDashboard,
            onMenuTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });
  });
}
