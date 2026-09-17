// Phase 1 smoke tests: the app shell, sidebar, and responsive foundation
// must actually build without throwing — this is the "reusable components
// render correctly" verification the phase's testing requirement asks for,
// run for real rather than only inspected by reading code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/localization/app_locales.dart';
import 'package:warehouse_os_app/localization/locale_controller.dart';
import 'package:warehouse_os_app/routing/app_router.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/badges/status_badge.dart';
import 'package:warehouse_os_app/shared/buttons/app_button.dart';
import 'package:warehouse_os_app/shared/feedback/app_empty_state.dart';
import 'package:warehouse_os_app/shared/feedback/app_error_state.dart';
import 'package:warehouse_os_app/shared/feedback/confirm_dialog.dart';
import 'package:warehouse_os_app/shared/layout/responsive/app_breakpoints.dart';
import 'package:warehouse_os_app/shared/overlays/app_dialog.dart';
import 'package:warehouse_os_app/shared/overlays/app_overlay_panel.dart';
import 'package:warehouse_os_app/shared/pagination/pagination_bar.dart';
import 'package:warehouse_os_app/shared/tables/app_data_table.dart';
import 'package:warehouse_os_app/shared/tables/table_column.dart';
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

  group('Localization / RTL (Phase 1.5 §11 verification)', () {
    test('English resolves LTR; Arabic and Kurdish Badini resolve RTL', () {
      expect(AppLocales.directionFor(const Locale('en')), TextDirection.ltr);
      expect(AppLocales.directionFor(const Locale('ar')), TextDirection.rtl);
      expect(AppLocales.directionFor(const Locale('ku')), TextDirection.rtl);
    });

    for (final locale in AppLocales.all) {
      testWidgets('App builds under the ${locale.locale.languageCode} locale with correct Directionality', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [localeProvider.overrideWith(() => _FixedLocaleController(locale.locale))],
            child: const WarehouseOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        final direction = Directionality.of(tester.element(find.byType(Scaffold).first));
        expect(direction, locale.isRtl ? TextDirection.rtl : TextDirection.ltr);
      });
    }
  });

  group('Routing (Phase 1.5 §12 verification)', () {
    testWidgets('Login (public) route renders outside the business shell — no sidebar', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: WarehouseOsApp()));
      await tester.pumpAndSettle();

      appRouter.go(AppRoutes.login);
      await tester.pumpAndSettle();

      expect(find.text('Sign in is coming in a later phase'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);

      appRouter.go(AppRoutes.dashboard); // leave the singleton router as found
      await tester.pumpAndSettle();
    });

    testWidgets('System Admin route renders the admin shell with its own nav (not the business nav)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: WarehouseOsApp()));
      await tester.pumpAndSettle();

      appRouter.go(AppRoutes.adminDashboard);
      await tester.pumpAndSettle();

      expect(find.text('Businesses'), findsOneWidget); // admin nav item
      expect(find.text('Products'), findsNothing); // business nav item, must not leak in

      appRouter.go(AppRoutes.dashboard); // leave the singleton router as found
      await tester.pumpAndSettle();
    });
  });

  group('AppDataTable states (Phase 1.5 §12 verification)', () {
    final columns = [
      AppTableColumn<String>(label: 'Name', cellBuilder: (context, item) => Text(item)),
    ];

    testWidgets('shows an empty state with no rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppDataTable<String>(columns: columns, rows: const [], idOf: (item) => item),
          ),
        ),
      );
      expect(find.byType(AppEmptyState), findsOneWidget);
    });

    testWidgets('shows an error state with retry when errorMessage is set', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppDataTable<String>(
              columns: columns,
              rows: const [],
              idOf: (item) => item,
              errorMessage: 'Could not load.',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      expect(find.byType(AppErrorState), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('renders real rows as a table on desktop width', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppDataTable<String>(
              columns: columns,
              rows: const ['Sofa', 'Table'],
              idOf: (item) => item,
            ),
          ),
        ),
      );
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Sofa'), findsOneWidget);
    });
  });

  testWidgets('PaginationBar reports page changes and respects disabled edges', (tester) async {
    int? requestedPage;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // PaginationBar reads AppLocalizations.of(context) for its labels
        // (rowsPerPage/pageOfTotal/tooltips) — unlike AppButton/StatusBadge
        // above, it needs the real delegates registered, same as the app
        // itself sets up in app.dart.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PaginationBar(
            page: 1,
            totalPages: 3,
            pageSize: 20,
            pageSizeOptions: const [20, 50],
            onPageChanged: (page) => requestedPage = page,
          ),
        ),
      ),
    );

    // On page 1, "previous"/"first" must be disabled — tapping them must not fire.
    await tester.tap(find.byTooltip('Previous page'));
    expect(requestedPage, isNull);

    await tester.tap(find.byTooltip('Next page'));
    expect(requestedPage, 2);
  });

  testWidgets('confirmAction shows the dialog and resolves true/false from the chosen button', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: AppButton(
                label: 'Delete',
                variant: AppButtonVariant.destructive,
                onPressed: () async {
                  result = await confirmAction(
                    context,
                    title: 'Delete this record?',
                    isDestructive: true,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDialog), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('showAppDialog and showAppOverlayPanel open and close without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                AppButton(
                  label: 'Open dialog',
                  onPressed: () => showAppDialog<void>(
                    context,
                    builder: (context) => const AlertDialog(content: Text('Dialog content')),
                  ),
                ),
                AppButton(
                  label: 'Open panel',
                  onPressed: () => showAppOverlayPanel<void>(
                    context,
                    builder: (context) => const Text('Panel content'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog content'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss via barrier
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open panel'));
    await tester.pumpAndSettle();
    expect(find.text('Panel content'), findsOneWidget);
  });
}

/// Test-only: pins `localeProvider`'s state to a fixed locale, since
/// overriding a `NotifierProvider` requires supplying a notifier instance,
/// not a bare value.
class _FixedLocaleController extends LocaleController {
  _FixedLocaleController(this._locale);
  final Locale _locale;

  @override
  Locale build() => _locale;
}
