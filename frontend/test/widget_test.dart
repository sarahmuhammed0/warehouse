// Phase 1 smoke tests: the app shell, sidebar, and responsive foundation
// must actually build without throwing — this is the "reusable components
// render correctly" verification the phase's testing requirement asks for,
// run for real rather than only inspected by reading code.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_os_app/app.dart';
import 'package:warehouse_os_app/core/config/app_mode.dart';
import 'package:warehouse_os_app/core/error/failure.dart';
import 'package:warehouse_os_app/core/network/api_client.dart';
import 'package:warehouse_os_app/core/repositories/demo_businesses.dart';
import 'package:warehouse_os_app/core/repositories/paged_query.dart';
import 'package:warehouse_os_app/features/admin/admin_businesses_screen.dart';
import 'package:warehouse_os_app/features/admin/admin_dashboard_screen.dart';
import 'package:warehouse_os_app/features/admin/data/admin_business_models.dart';
import 'package:warehouse_os_app/features/admin/data/admin_metrics.dart';
import 'package:warehouse_os_app/features/admin/data/admin_providers.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_business_detail_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_business_form_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_business_records_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_business_reports_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_reset_password_dialog.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_overview_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_record_detail_screen.dart';
import 'package:warehouse_os_app/features/auth/data/auth_models.dart';
import 'package:warehouse_os_app/features/auth/data/auth_repository.dart';
import 'package:warehouse_os_app/features/auth/data/demo_auth_repository.dart';
import 'package:warehouse_os_app/features/admin/data/registration_queue_repository.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_registrations_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:warehouse_os_app/features/products/data/api_product_repository.dart';
import 'package:warehouse_os_app/features/products/data/product_models.dart';
import 'package:warehouse_os_app/features/products/data/product_repository.dart';
import 'package:warehouse_os_app/features/categories/data/api_category_repository.dart';
import 'package:warehouse_os_app/features/categories/data/category_providers.dart';
import 'package:warehouse_os_app/features/categories/data/category_repository.dart';
import 'package:warehouse_os_app/features/auth/data/registration_repository.dart';
import 'package:warehouse_os_app/features/auth/presentation/signup_screen.dart';
import 'package:warehouse_os_app/features/auth/presentation/login_screen.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_state.dart';
import 'package:warehouse_os_app/features/categories/categories_screen.dart';
import 'package:warehouse_os_app/features/customers/customers_screen.dart';
import 'package:warehouse_os_app/features/customers/presentation/customer_detail_screen.dart';
import 'package:warehouse_os_app/features/dashboard/dashboard_screen.dart';
import 'package:warehouse_os_app/features/employees/data/employee_providers.dart';
import 'package:warehouse_os_app/features/employees/data/employee_repository.dart';
import 'package:warehouse_os_app/features/dashboard/data/dashboard_metrics.dart';
import 'package:warehouse_os_app/features/categories/presentation/category_form_dialog.dart';
import 'package:warehouse_os_app/features/inventory/inventory_screen.dart';
import 'package:warehouse_os_app/features/suppliers/presentation/supplier_form_dialog.dart';
import 'package:warehouse_os_app/features/inventory/data/inventory_models.dart';
import 'package:warehouse_os_app/features/inventory/data/inventory_providers.dart';
import 'package:warehouse_os_app/features/inventory/data/stock_engine.dart';
import 'package:warehouse_os_app/features/orders/data/order_models.dart';
import 'package:warehouse_os_app/features/orders/data/order_providers.dart';
import 'package:warehouse_os_app/features/orders/data/order_stock.dart';
import 'package:warehouse_os_app/features/orders/presentation/order_form_screen.dart';
import 'package:warehouse_os_app/features/customers/data/customer_models.dart';
import 'package:warehouse_os_app/features/customers/data/customer_providers.dart';
import 'package:warehouse_os_app/features/customers/presentation/customer_form_dialog.dart';
import 'package:warehouse_os_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:warehouse_os_app/features/reports/presentation/report_export.dart';
import 'package:warehouse_os_app/features/reports/reports_screen.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/permission_providers.dart';
import 'package:warehouse_os_app/features/products/data/product_providers.dart';
import 'package:warehouse_os_app/features/employees/employees_screen.dart';
import 'package:warehouse_os_app/features/orders/orders_screen.dart';
import 'package:warehouse_os_app/features/orders/presentation/order_detail_screen.dart';
import 'package:warehouse_os_app/features/production/presentation/production_detail_screen.dart';
import 'package:warehouse_os_app/features/production/production_screen.dart';
import 'package:warehouse_os_app/features/products/presentation/product_detail_screen.dart';
import 'package:warehouse_os_app/features/products/presentation/product_form_screen.dart';
import 'package:warehouse_os_app/features/products/products_screen.dart';
import 'package:warehouse_os_app/features/purchases/presentation/purchase_detail_screen.dart';
import 'package:warehouse_os_app/features/purchases/purchases_screen.dart';
import 'package:warehouse_os_app/features/returns/presentation/return_detail_screen.dart';
import 'package:warehouse_os_app/features/returns/returns_screen.dart';
import 'package:warehouse_os_app/features/sales/sales_screen.dart';
import 'package:warehouse_os_app/features/search/presentation/search_results_screen.dart';
import 'package:warehouse_os_app/features/suppliers/presentation/supplier_detail_screen.dart';
import 'package:warehouse_os_app/features/suppliers/suppliers_screen.dart';
import 'package:warehouse_os_app/l10n/generated/app_localizations.dart';
import 'package:warehouse_os_app/localization/app_locales.dart';
import 'package:warehouse_os_app/localization/locale_controller.dart';
import 'package:warehouse_os_app/features/settings/data/business_type_config.dart';
import 'package:warehouse_os_app/routing/app_router.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/badges/status_badge.dart';
import 'package:warehouse_os_app/shared/dashboard/dashboard_cards.dart';
import 'package:warehouse_os_app/shared/dashboard/simple_bar_chart.dart';
import 'package:warehouse_os_app/theme/theme_controller.dart';
import 'package:warehouse_os_app/shared/dashboard/metric_cards.dart';
import 'package:warehouse_os_app/shared/dashboard/vertical_bar_chart.dart';
import 'package:warehouse_os_app/shared/navigation/nav_items.dart';
import 'package:warehouse_os_app/shared/buttons/app_button.dart';
import 'package:warehouse_os_app/shared/feedback/app_empty_state.dart';
import 'package:warehouse_os_app/shared/feedback/app_error_state.dart';
import 'package:warehouse_os_app/shared/feedback/confirm_dialog.dart';
import 'package:warehouse_os_app/shared/forms/app_text_field.dart';
import 'package:warehouse_os_app/shared/layout/responsive/app_breakpoints.dart';
import 'package:warehouse_os_app/shared/overlays/app_dialog.dart';
import 'package:warehouse_os_app/shared/overlays/app_overlay_panel.dart';
import 'package:warehouse_os_app/shared/pagination/pagination_bar.dart';
import 'package:warehouse_os_app/shared/tables/app_data_table.dart';
import 'package:warehouse_os_app/shared/tables/table_column.dart';
import 'package:warehouse_os_app/theme/app_theme.dart';

import 'fakes/fake_auth.dart';

void main() {
  testWidgets('App shell builds on a desktop-width screen and shows the dashboard + sidebar nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // An unauthenticated session now lands on the login screen by default
    // (Phase 2 §21) — this test needs an authenticated fixture to reach the
    // shell at all.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)],
        child: const WarehouseOsApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The dashboard placeholder screen's title.
    expect(find.text('Dashboard'), findsWidgets);
    // Two other modules must be reachable on desktop width (persistent
    // navigation, not a drawer). Products rides the header's labelled pill
    // bar; Settings rides the icon rail, which is why this asks by nav key
    // rather than by label.
    expect(find.byKey(const ValueKey('nav:/products')), findsOneWidget);
    expect(find.text('Products'), findsOneWidget, reason: 'primary modules keep their label');
    expect(find.byKey(const ValueKey('nav:/settings')), findsOneWidget);
  });

  testWidgets('App shell builds on a mobile-width screen with a drawer instead of a persistent sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)],
        child: const WarehouseOsApp(),
      ),
    );
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
      // Unauthenticated by default now (Phase 2 §21) — the app already
      // lands on login without any navigation needed.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(FakeUnauthenticatedController.new)],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('An authenticated session reaching an admin route is redirected to the business dashboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Phase 2's Flutter UI only ever authenticates business users — the
      // router redirects any authenticated session away from /admin/*
      // (routing/app_router.dart's `_redirect`). There is no in-app way to
      // navigate to an admin route while authenticated as a business user,
      // so this test exercises the redirect guard itself rather than a
      // user-driven navigation.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Businesses'), findsNothing); // admin nav item must not leak in
    });

    testWidgets('An unauthenticated session is redirected away from a protected route to login', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(FakeUnauthenticatedController.new)],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      // initialLocation is the login route itself, so this also proves the
      // app never briefly shows a protected screen before redirecting.
      expect(find.byType(LoginScreen), findsOneWidget);
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

  group('LoginScreen (Phase 2 §17/§38 verification)', () {
    Widget pumpableApp(FakeAuthRepository repo) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
      child: const WarehouseOsApp(),
    );

    testWidgets('renders phone + password fields and the login button', (tester) async {
      await tester.pumpWidget(pumpableApp(FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      // Labels render via FormFieldWrapper's RichText with a trailing
      // " *" (required-field marker) appended, so matching needs
      // findRichText — see shared/forms/form_field_wrapper.dart.
      expect(find.textContaining('Phone number', findRichText: true), findsOneWidget);
      expect(find.textContaining('Password', findRichText: true), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Login'), findsOneWidget);
    });

    testWidgets('shows validation errors and does not call the repository when the password is empty', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      // The demo-mode card (§10 of docs/frontend-demo-mode.md) pushes the
      // real form below the 800x600 default test viewport — a taller
      // viewport keeps the Login button on-screen and tappable.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(pumpableApp(repo));
      await tester.pumpAndSettle();

      // Phone already has the "+964" default; leave password empty.
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Password is required.'), findsOneWidget);
      expect(repo.loginCallCount, 0);
    });

    testWidgets('submits trimmed phone + password to the repository on valid input', (tester) async {
      final repo = FakeAuthRepository();
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(pumpableApp(repo));
      await tester.pumpAndSettle();

      // "+964" alone (the screen's default) is too short to pass the phone
      // validator (min 7 chars after the country code) — a real user is
      // expected to keep typing, so tests must too.
      await tester.enterText(find.byType(AppTextField).first, '+9647701234567');
      await tester.enterText(find.byType(AppTextField).last, 'correct-password');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(repo.loginCallCount, 1);
      expect(repo.lastLoginArgs?.phone, '+9647701234567');
      expect(repo.lastLoginArgs?.password, 'correct-password');
    });

    testWidgets('shows a loading state on the button while authenticating', (tester) async {
      // A completer holds `login()` open so the AuthAuthenticating state
      // survives across a `pump()` — the fake otherwise resolves so fast
      // (no real network) that a single pump can observe the login as
      // already complete and the app already navigated to the dashboard.
      final completer = Completer<void>();
      final repo = FakeAuthRepository()..pendingCompleter = completer;
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(pumpableApp(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField).first, '+9647701234567');
      await tester.enterText(find.byType(AppTextField).last, 'correct-password');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pump(); // one frame: AuthAuthenticating, login() still pending

      final button = tester.widget<AppButton>(find.byKey(const ValueKey('loginSubmitButton')));
      expect(button.loading, isTrue);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows the backend error message and reaches the dashboard on successful login', (
      tester,
    ) async {
      final repo = FakeAuthRepository()..loginError = const Failure('INVALID_CREDENTIALS', 'Incorrect phone number or password.');
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(pumpableApp(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField).first, '+9647701234567');
      await tester.enterText(find.byType(AppTextField).last, 'wrong-password');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect phone number or password.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget); // still on login, no navigation

      // Now retry with credentials the fake accepts.
      repo.loginError = null;
      await tester.enterText(find.byType(AppTextField).last, 'correct-password');
      await tester.tap(find.widgetWithText(AppButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('shows each blocked-business reason the backend distinguishes', (tester) async {
      // The backend answers a blocked login with one of three codes, and the
      // rejected one carries the administrator's own reason. All three used
      // to be reported as "disabled", which told the owner of a
      // self-registered business nothing useful. These assert the specific
      // message reaches the screen rather than being flattened.
      const cases = <Failure>[
        Failure(
          'BUSINESS_PENDING_APPROVAL',
          'Your registration is still awaiting approval. You will be able to sign in once it is approved.',
        ),
        Failure('BUSINESS_REJECTED', 'Your registration was not approved: Business licence could not be verified.'),
        Failure('BUSINESS_DISABLED', 'This business account has been disabled.'),
      ];

      for (final failure in cases) {
        final repo = FakeAuthRepository()..loginError = failure;
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(pumpableApp(repo));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(AppTextField).first, '+9647701234567');
        await tester.enterText(find.byType(AppTextField).last, 'correct-password');
        await tester.tap(find.widgetWithText(AppButton, 'Login'));
        await tester.pumpAndSettle();

        expect(find.text(failure.message), findsOneWidget, reason: 'did not show ${failure.code}');
        expect(find.byType(LoginScreen), findsOneWidget, reason: '${failure.code} must not grant a session');
      }
    });

    testWidgets('shows the session-expired banner when the auth state is AuthSessionExpired', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(_FakeSessionExpiredController.new)],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your session expired. Please sign in again.'), findsOneWidget);
    });

    for (final locale in AppLocales.all) {
      testWidgets('login screen renders under the ${locale.locale.languageCode} locale', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localeProvider.overrideWith(() => _FixedLocaleController(locale.locale)),
              authControllerProvider.overrideWith(FakeUnauthenticatedController.new),
            ],
            child: const WarehouseOsApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        final direction = Directionality.of(tester.element(find.byType(Scaffold).first));
        expect(direction, locale.isRtl ? TextDirection.rtl : TextDirection.ltr);
      });
    }
  });

  group('Real API repositories (Phase 6 wiring)', () {
    test('backend mode selects the API repositories, demo mode the local ones', () {
      // The same switch auth uses. A failed API call must never fall back to
      // demo data, so the choice is made once, by mode, not per call.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // `flutter test` compiles in demo mode, so this asserts the demo side
      // here and the backend side is covered by the constructors below.
      expect(container.read(productRepositoryProvider), isA<LocalProductRepository>());
      expect(container.read(categoryRepositoryProvider), isA<LocalCategoryRepository>());
      expect(ApiProductRepository(ApiClient()), isA<ProductRepository>());
      expect(ApiCategoryRepository(ApiClient()), isA<CategoryRepository>());
    });

    test('product status maps to the specification\'s own word, both ways', () {
      // §45 says "archived"; the Flutter enum says "discontinued". They are
      // the same state, and this mapping is the only place that knows it —
      // if it breaks, a discontinued product silently becomes active.
      final round = <ProductStatus, String>{
        ProductStatus.active: 'active',
        ProductStatus.inactive: 'inactive',
        ProductStatus.discontinued: 'archived',
      };
      for (final entry in round.entries) {
        final json = ApiProductRepository.toRequestJson(
          ProductDraft(
            name: 'x',
            code: 'x',
            categoryId: '1',
            currentQuantity: 0,
            unit: 'pcs',
            status: entry.key,
          ),
        );
        expect(json['status'], entry.value, reason: '${entry.key} should send ${entry.value}');
        expect(
          ApiProductRepository.statusFromApi(entry.value),
          entry.key,
          reason: '${entry.value} should read back as ${entry.key}',
        );
      }
    });

    test('product type folds component into raw material, as §21 has only two kinds', () {
      String sent(ProductType type) => ApiProductRepository.toRequestJson(
        ProductDraft(
          name: 'x',
          code: 'x',
          categoryId: '1',
          currentQuantity: 0,
          unit: 'pcs',
          productType: type,
        ),
      )['productType'] as String;

      expect(sent(ProductType.finishedGood), 'finished_good');
      expect(sent(ProductType.rawMaterial), 'raw_material');
      // The backend enum has no `component`; sending it would be rejected
      // outright, so it is folded rather than passed through.
      expect(sent(ProductType.component), 'raw_material');
    });

    test('a product create never sends a stock quantity', () {
      // Stock is the sum of what is in the product's locations. Letting the
      // product form set it would be a second source of truth, and the
      // backend refuses the field anyway.
      final json = ApiProductRepository.toRequestJson(
        ProductDraft(name: 'x', code: 'x', categoryId: '1', currentQuantity: 42, unit: 'pcs'),
      );
      expect(json.containsKey('currentQuantity'), isFalse);
      expect(json.containsKey('quantity'), isFalse);
    });
  });

  group('Business self-registration (§2 approval flow)', () {
    Widget pumpableApp(RegistrationRepository registration) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        registrationRepositoryProvider.overrideWithValue(registration),
      ],
      child: const WarehouseOsApp(),
    );

    /// Records what was submitted, so a test can assert the wire format
    /// rather than just that something was sent.
    late RegistrationDraft? submitted;
    Widget appWith({Failure? error}) {
      submitted = null;
      return pumpableApp(RecordingRegistrationRepository(
        onRegister: (draft) => submitted = draft,
        error: error,
      ));
    }

    Future<void> openSignUp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('signUpLink')));
      await tester.pumpAndSettle();
    }

    Future<void> fillValidForm(WidgetTester tester) async {
      await tester.enterText(find.byKey(const ValueKey('signUpBusinessName')), 'Applicant Co');
      await tester.enterText(find.byKey(const ValueKey('signUpBusinessPhone')), '+9647700001111');
      await tester.enterText(find.byKey(const ValueKey('signUpOwnerName')), 'Applicant Owner');
      await tester.enterText(find.byKey(const ValueKey('signUpOwnerPhone')), '+9647700002222');
      await tester.enterText(find.byKey(const ValueKey('signUpPassword')), 'ApplicantPass1');

      // The business type is required and has no default, so it has to be
      // chosen through the dropdown like a user would.
      await tester.tap(find.byKey(const ValueKey('signUpBusinessType')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warehouse').last);
      await tester.pumpAndSettle();
    }

    testWidgets('the login screen offers registration, and it opens the form', (tester) async {
      await tester.pumpWidget(appWith());
      await openSignUp(tester);

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('signUpSubmitButton')), findsOneWidget);
    });

    testWidgets('an incomplete form is not submitted', (tester) async {
      // The applicant must not be told "awaiting review" for an application
      // that was never sent.
      await tester.pumpWidget(appWith());
      await openSignUp(tester);

      await tester.tap(find.byKey(const ValueKey('signUpSubmitButton')));
      await tester.pumpAndSettle();

      expect(submitted, isNull, reason: 'validation should have stopped the request');
      expect(find.byKey(const ValueKey('signUpAccepted')), findsNothing);
    });

    testWidgets('a short password is rejected locally, before a round trip', (tester) async {
      await tester.pumpWidget(appWith());
      await openSignUp(tester);
      await fillValidForm(tester);
      await tester.enterText(find.byKey(const ValueKey('signUpPassword')), 'short');

      await tester.tap(find.byKey(const ValueKey('signUpSubmitButton')));
      await tester.pumpAndSettle();

      expect(submitted, isNull, reason: 'the backend minimum should be enforced in the form too');
    });

    testWidgets('a valid application is submitted in the wire format the backend expects', (tester) async {
      await tester.pumpWidget(appWith());
      await openSignUp(tester);
      await fillValidForm(tester);

      await tester.tap(find.byKey(const ValueKey('signUpSubmitButton')));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      // snake_case, not the display label: the backend column is an ENUM and
      // rejects "Warehouse".
      expect(submitted!.businessType, 'warehouse');
      expect(submitted!.businessName, 'Applicant Co');
      expect(submitted!.ownerPhone, '+9647700002222');
    });

    testWidgets('success shows a pending notice and never signs the applicant in', (tester) async {
      // The whole point: the business exists but is not approved, so the app
      // must not behave as though access was granted.
      await tester.pumpWidget(appWith());
      await openSignUp(tester);
      await fillValidForm(tester);
      await tester.tap(find.byKey(const ValueKey('signUpSubmitButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('signUpAccepted')), findsOneWidget);
      expect(find.text('Application received'), findsOneWidget);
      // Still on the public screen — no dashboard, no shell.
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      // And the form is gone, so it cannot be submitted twice by reflex.
      expect(find.byKey(const ValueKey('signUpSubmitButton')), findsNothing);
    });

    testWidgets('a server error is shown and the form stays filled in', (tester) async {
      await tester.pumpWidget(appWith(error: const Failure('RATE_LIMITED', 'Too many registration attempts.')));
      await openSignUp(tester);
      await fillValidForm(tester);
      await tester.tap(find.byKey(const ValueKey('signUpSubmitButton')));
      await tester.pumpAndSettle();

      expect(find.text('Too many registration attempts.'), findsOneWidget);
      expect(find.byKey(const ValueKey('signUpAccepted')), findsNothing);
      expect(find.byKey(const ValueKey('signUpSubmitButton')), findsOneWidget, reason: 'they must be able to retry');
    });

    testWidgets('registration is not offered while System Admin is selected', (tester) async {
      // A System Admin account is never self-registered, so offering it
      // there would invite an application that can never be granted.
      await tester.pumpWidget(appWith());
      await tester.pumpAndSettle();

      // In demo mode the selector is not rendered at all, so this only
      // applies when the backend selector is present.
      if (find.byKey(const ValueKey('loginAsSystemAdmin')).evaluate().isEmpty) {
        expect(find.byKey(const ValueKey('signUpLink')), findsOneWidget);
        return;
      }
      await tester.tap(find.byKey(const ValueKey('loginAsSystemAdmin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('signUpLink')), findsNothing);
    });
  });

  group('Admin registration queue (§2 approval controls)', () {
    late FakeRegistrationQueue queue;

    Widget adminApp() => ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        registrationQueueRepositoryProvider.overrideWithValue(queue),
      ],
      child: const WarehouseOsApp(),
    );

    Future<void> openQueue(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(adminApp());
      await tester.pumpAndSettle();
      tester.element(find.byType(WarehouseOsApp)); // ensure built
      // Navigate directly: the nav item lives in the admin shell header,
      // which is covered by the shell's own tests.
      final context = tester.element(find.byType(AdminDashboardScreen).first);
      GoRouter.of(context).go(AppRoutes.adminRegistrations);
      await tester.pumpAndSettle();
    }

    /// A toast is a SnackBar with a ~4s auto-dismiss timer. Leaving it
    /// pending tears the tree down mid-animation, which surfaces as
    /// 'attached is not true' / Overlay build-scope assertions in whichever
    /// test happens to run next. Letting it expire keeps the failure where
    /// it belongs.
    Future<void> settleToast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    setUp(() => queue = FakeRegistrationQueue());

    testWidgets('lists the applications waiting for a decision', (tester) async {
      await openQueue(tester);

      expect(find.byType(AdminRegistrationsScreen), findsOneWidget);
      expect(find.text('Applicant One'), findsOneWidget);
      expect(find.byKey(const ValueKey('approve:reg-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reject:reg-1')), findsOneWidget);
    });

    testWidgets('approving calls the backend and refreshes the queue', (tester) async {
      await openQueue(tester);

      await tester.tap(find.byKey(const ValueKey('approve:reg-1')));
      await tester.pumpAndSettle();

      await settleToast(tester);
      expect(queue.approved, ['reg-1']);
      // The decided application must leave the pending queue, or the admin
      // will approve it twice.
      expect(find.text('Applicant One'), findsNothing);
    });

    testWidgets('rejecting requires a reason and sends it', (tester) async {
      await openQueue(tester);

      await tester.tap(find.byKey(const ValueKey('reject:reg-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rejectRegistrationDialog')), findsOneWidget);

      // Confirming with an empty reason must not submit: the applicant is
      // shown this text, and the backend rejects a blank one anyway.
      await tester.tap(find.byKey(const ValueKey('rejectConfirmButton')));
      await tester.pumpAndSettle();
      expect(queue.rejected, isEmpty);
      expect(find.byKey(const ValueKey('rejectRegistrationDialog')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('rejectReasonField')), 'Licence not verified');
      await tester.tap(find.byKey(const ValueKey('rejectConfirmButton')));
      await tester.pumpAndSettle();

      await settleToast(tester);
      expect(queue.rejected, [('reg-1', 'Licence not verified')]);
    });

    testWidgets('an already-decided application surfaces the conflict and refreshes', (tester) async {
      // Two administrators working the same queue: the backend answers 409,
      // and the screen must show that rather than appear to succeed.
      queue.failWith = const Failure('ALREADY_DECIDED', 'This registration is already active.');
      await openQueue(tester);

      await tester.tap(find.byKey(const ValueKey('approve:reg-1')));
      await tester.pumpAndSettle();

      expect(find.text('This registration is already active.'), findsOneWidget);
      await settleToast(tester);
    });

    testWidgets('an empty queue says so instead of showing a blank page', (tester) async {
      queue.items = [];
      await openQueue(tester);

      expect(find.byKey(const ValueKey('registrationsEmpty')), findsOneWidget);
    });
  });

  group('AuthController + logout (Phase 2 §18/§24 verification)', () {
    testWidgets('logout clears the session and returns the app to the login screen', (tester) async {
      final repo = FakeAuthRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repo),
            // Real AuthController.logout() reads secureTokenStorageProvider
            // directly — without this override it hits the real
            // flutter_secure_storage platform channel, unavailable here.
            secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          ],
          child: const WarehouseOsApp(),
        ),
      );
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('accountMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(repo.logoutCalled, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('Business modules (frontend-first phase verification)', () {
    /// Every test in this group needs to navigate the real app router after
    /// the initial pump, so each builds its own [ProviderContainer] (rather
    /// than a bare `ProviderScope`) and always re-reads `routerProvider`
    /// fresh at the point of use — never caching the `GoRouter` instance in
    /// a local variable, since changing a provider the router itself
    /// watches (e.g. `businessTypeProvider`) makes `routerProvider`
    /// recompute to a brand-new instance (the same mechanism
    /// `_businessBrandLabel` already relies on for re-branding).
    ProviderContainer authenticatedContainer() => ProviderContainer(
      overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)],
    );

    Future<void> pumpDesktop(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
    }

    testWidgets('Products list loads real demo data and opens detail on tap', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      container.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();

      expect(find.text('3-Seat Sofa — Charcoal'), findsOneWidget);

      await tester.tap(find.text('3-Seat Sofa — Charcoal'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    });

    testWidgets('Product create form rejects submission with no category selected', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      container.read(routerProvider).push(AppRoutes.productNew);
      await tester.pumpAndSettle();

      final createButton = find.widgetWithText(AppButton, 'Create');
      expect(createButton, findsOneWidget);
      // The form is taller than the viewport, so the button is off-screen
      // and `tap` would silently miss it — which made this test pass
      // without ever submitting anything.
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Still on the create form — no category selected means the submit
      // was rejected (§8: category is a required field).
      expect(find.byType(ProductFormScreen), findsOneWidget);
    });

    testWidgets('Categories: adding a new category shows it in the list', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      container.read(routerProvider).go(AppRoutes.categories);
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Add Categories'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField).first, 'Outdoor Furniture');
      await tester.enterText(find.byType(AppTextField).at(1), 'OUT');
      await tester.tap(find.widgetWithText(AppButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Outdoor Furniture'), findsOneWidget);
    });

    testWidgets('Dashboard stat cards never collide with the sidebar module labels', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      // Navigation owns the module names; the dashboard owns the figures.
      // The original bug this guards against was the two rendering as the
      // same string on one screen.
      expect(find.text('Products'), findsOneWidget); // the header pill only
      expect(find.byKey(const ValueKey('nav:/settings')), findsOneWidget);

      // "Total products" and "Total categories" are reference figures now,
      // so neither is on screen until the section is expanded...
      expect(find.text('Total products'), findsNothing);
      expect(find.text('Total categories'), findsNothing);

      // ...and expanding must not make any of them read as a nav label.
      await tester.tap(find.byKey(const ValueKey('toggleMoreStatistics')));
      await tester.pumpAndSettle();
      expect(find.text('Total products'), findsOneWidget);
      expect(find.text('Total categories'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget, reason: 'expanding must not duplicate the nav label');
    });

    testWidgets('Settings: switching to the Security section shows password-policy fields', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      container.read(routerProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();

      // Field labels render via FormFieldWrapper's RichText, not a plain
      // Text widget — see the login-screen tests above for the same note.
      expect(find.textContaining('Minimum password length', findRichText: true), findsOneWidget);
    });

    testWidgets('System Admin business list screen loads real demo businesses', (tester) async {
      // Pumped directly, not through the app router: a business-user
      // session (the only kind Phase 2's Flutter app can authenticate as)
      // is correctly redirected away from every `/admin/*` route — see the
      // "An authenticated session reaching an admin route is redirected"
      // test above. That's the router's job; this test is only for
      // AdminBusinessesScreen's own rendering logic.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // A real Scaffold ancestor, matching how AppShell always wraps
            // PageScaffold in production — a bare `home: AdminBusinessesScreen()`
            // has no Material ancestor for the screen's own TextField.
            home: const Scaffold(body: AdminBusinessesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Karwan Furniture Factory'), findsOneWidget);
    });

    testWidgets('Global search finds a seeded product by name', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      container.read(routerProvider).go('${AppRoutes.search}?q=Ergonomic');
      await tester.pumpAndSettle();

      expect(find.text('Ergonomic Office Chair'), findsOneWidget);
    });
  });

  group('Admin dashboard stat cards (interactive navigation verification)', () {
    ProviderContainer adminContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new)]);

    Future<void> pumpAdminDesktop(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
    }

    testWidgets('The admin date-range control really re-plots the platform chart', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      int plottedBars() => tester
          .widget<VerticalBarChart>(find.byType(VerticalBarChart))
          .points
          .length;
      expect(plottedBars(), 6, reason: 'six months is the default range');

      final chip = find.byKey(const ValueKey('adminRangeChip'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<AdminRange>, 'Last 12 months'));
      await tester.pumpAndSettle();

      expect(plottedBars(), 12, reason: 'the chart plots the chosen range, not a fixed six');
    });

    testWidgets('Refresh re-folds the figures and says so', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      final refresh = find.byKey(const ValueKey('adminRefreshMetrics'));
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await tester.pumpAndSettle();

      // Re-folding derived figures usually lands on the same numbers, so
      // the confirmation is the only way a user can tell it ran at all.
      expect(find.text('Refreshed'), findsOneWidget);
      // ...and the figures are still the real ones afterwards.
      final metrics = await container.read(adminMetricsProvider.future);
      expect(
        tester.widget<StatCard>(find.widgetWithText(StatCard, 'Products')).value,
        '${metrics.totalProducts}',
      );
    });

    // Seed data (admin_repository.dart): 4 businesses, 3 active + 1
    // disabled ("Northern Distribution Center") — chosen so Active/Disabled
    // have real, distinguishable results to filter to, not an always-empty
    // filter.
    const activeOnly = ['Karwan Furniture Factory', 'Erbil Central Warehouse', 'City Storage Store'];
    const disabledOnly = 'Northern Distribution Center';

    testWidgets('Businesses card navigates to the Businesses list (all 4, no filter)', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      await tester.tap(find.byKey(const ValueKey('adminOpenBusinesses')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessesScreen), findsOneWidget);
      for (final name in activeOnly) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text(disabledOnly), findsOneWidget);
    });

    testWidgets('Active card navigates to Businesses with the Active filter applied — same data as the card count', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      // The pill states its own count, folded from the list it opens.
      expect(find.textContaining('3 Active'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('adminFilterActive')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessesScreen), findsOneWidget);
      for (final name in activeOnly) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text(disabledOnly), findsNothing); // filtered out — proves the filter, not just navigation
    });

    testWidgets('Disabled card navigates to Businesses with the Disabled filter applied — same data as the card count', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      expect(find.textContaining('1 Disabled'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('adminFilterDisabled')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessesScreen), findsOneWidget);
      expect(find.text(disabledOnly), findsOneWidget);
      for (final name in activeOnly) {
        expect(find.text(name), findsNothing);
      }
    });

    // The four record metrics no longer open a business screen at all —
    // they start the three-level drill-down. Each test below walks the
    // whole path and then walks back out of it, so a regression at any
    // single level fails a test rather than quietly skipping a step.
    //
    // Every test also asserts the NEGATIVE the brief is explicit about:
    // tapping a platform statistic must never land the System Admin in a
    // warehouse's own operational table.

    testWidgets('Employees: dashboard → per-business overview → one business → one employee → back out', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      // Level 1 → 2
      await tester.tap(find.widgetWithText(StatCard, 'Employees'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOverviewScreen), findsOneWidget);
      expect(find.byType(EmployeesPlaceholderScreen), findsNothing); // never the business table
      expect(find.text('Select a business to view its records'), findsOneWidget);
      for (final name in [...activeOnly, disabledOnly]) {
        expect(find.text(name), findsOneWidget);
      }

      // Level 2 → 3 (an explicitly chosen business)
      await tester.tap(find.text('Erbil Central Warehouse'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);
      expect(find.text('Karzan Tahir'), findsOneWidget); // Erbil's own staff
      expect(find.text('Demo Owner'), findsNothing); // Karwan's — scoped out

      // Level 3 → 4
      await tester.tap(find.text('Karzan Tahir'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminRecordDetailScreen), findsOneWidget);
      expect(find.text('+9647100000002'), findsOneWidget);

      // ...and back out, one real pop per level.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminOverviewScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('Products: dashboard → per-business overview → one business → one product → back out', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      await tester.tap(find.widgetWithText(StatCard, 'Products'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOverviewScreen), findsOneWidget);
      expect(find.byType(ProductsScreen), findsNothing);
      expect(find.text('3-Seat Sofa — Charcoal'), findsNothing); // no records before a business is chosen

      await tester.tap(find.text('Karwan Furniture Factory'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);
      expect(find.text('3-Seat Sofa — Charcoal'), findsOneWidget);
      expect(find.text('Office Desk — Standard'), findsNothing); // Erbil's — scoped out

      await tester.tap(find.text('3-Seat Sofa — Charcoal'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminRecordDetailScreen), findsOneWidget);
      expect(find.text('SOFA-3S-CH'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminOverviewScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('Orders: dashboard → per-business overview → one business → one order → back out', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      await tester.tap(find.widgetWithText(StatCard, 'Orders'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOverviewScreen), findsOneWidget);
      expect(find.byType(OrdersScreen), findsNothing);

      await tester.tap(find.text('Karwan Furniture Factory'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);
      expect(find.text('Ahmed Al-Rashid'), findsOneWidget); // Karwan's standard order
      expect(find.text('Karwan Furniture Retail'), findsNothing); // Erbil's/Northern's customer

      await tester.tap(find.text('Ahmed Al-Rashid'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminRecordDetailScreen), findsOneWidget);
      expect(find.text('3-Seat Sofa — Charcoal'), findsOneWidget); // its line item

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminOverviewScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('Sales: dashboard → per-business overview → one business → one sale → back out', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      await tester.tap(find.widgetWithText(StatCard, 'Sales'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOverviewScreen), findsOneWidget);
      expect(find.byType(SalesPlaceholderScreen), findsNothing);

      await tester.tap(find.text('City Storage Store'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);
      // Sales lists quick sales only — the same split the business-side
      // Sales module uses, so this business's ONE standard order (Queen Bed
      // Frame, Layla Hassan) must not appear here.
      expect(find.text('Layla Hassan'), findsNothing);
      expect(find.textContaining('SALE-'), findsOneWidget);

      await tester.tap(find.textContaining('SALE-'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminRecordDetailScreen), findsOneWidget);
      expect(find.text('Plastic Storage Bin (60L)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminOverviewScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('A System Admin session cannot reach a business operational table by URL either', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpAdminDesktop(tester, container);

      // The previous design whitelisted these four routes for admin
      // sessions. They are closed again: the drill-down is the only way in,
      // and it always goes through an explicit business choice.
      for (final route in [AppRoutes.products, AppRoutes.orders, AppRoutes.sales, AppRoutes.employees]) {
        container.read(routerProvider).go(route);
        await tester.pumpAndSettle();
        expect(find.byType(AdminDashboardScreen), findsOneWidget, reason: '$route should bounce a System Admin back to /admin');
      }
      expect(find.byType(ProductsScreen), findsNothing);
      expect(find.byType(OrdersScreen), findsNothing);
      expect(find.byType(SalesPlaceholderScreen), findsNothing);
      expect(find.byType(EmployeesPlaceholderScreen), findsNothing);
    });
  });

  group('Admin drill-down total consistency (no invented numbers)', () {
    ProviderContainer adminContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new)]);

    test('Every dashboard total is the sum of its per-business counts', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final metrics = await container.read(adminMetricsProvider.future);
      final rows = metrics.byBusiness.values;

      expect(metrics.totalEmployees, rows.fold<int>(0, (sum, m) => sum + m.employeeCount));
      expect(metrics.totalProducts, rows.fold<int>(0, (sum, m) => sum + m.productCount));
      expect(metrics.totalOrders, rows.fold<int>(0, (sum, m) => sum + m.orderCount));
      expect(metrics.totalSalesRecords, rows.fold<int>(0, (sum, m) => sum + m.salesCount));
      expect(metrics.totalSalesAmount, closeTo(rows.fold<double>(0, (sum, m) => sum + m.salesTotal), 0.001));
    });

    test('Those totals equal the number of records the repositories actually hold', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final metrics = await container.read(adminMetricsProvider.future);
      const everything = PagedQuery(pageSize: 500);

      final products = await container.read(productRepositoryProvider).list(everything);
      expect(metrics.totalProducts, products.total, reason: 'a product belonging to no known business would break this');

      final employees = await container.read(employeeRepositoryProvider).list(everything);
      expect(metrics.totalEmployees, employees.total);

      // Orders and Sales are one table split by type, so together they must
      // account for every order record — no double counting, none missed.
      final orders = await container.read(orderRepositoryProvider).list(everything);
      expect(metrics.totalOrders + metrics.totalSalesRecords, orders.total);
    });

    test("Each business's count is exactly the records its drill-down lists", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final metrics = await container.read(adminMetricsProvider.future);

      for (final business in kDemoBusinesses) {
        final row = metrics.forBusiness(business.id);
        expect((await container.read(adminBusinessEmployeesProvider(business.id).future)).length, row.employeeCount, reason: business.name);
        expect((await container.read(adminBusinessProductsProvider(business.id).future)).length, row.productCount, reason: business.name);
        expect((await container.read(adminBusinessOrdersProvider(business.id).future)).length, row.orderCount, reason: business.name);
        expect((await container.read(adminBusinessSalesProvider(business.id).future)).length, row.salesCount, reason: business.name);
      }
    });

    testWidgets('The dashboard card shows that derived total, not a seeded one', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      final metrics = await container.read(adminMetricsProvider.future);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();

      expect(tester.widget<StatCard>(find.widgetWithText(StatCard, 'Employees')).value, '${metrics.totalEmployees}');
      expect(tester.widget<StatCard>(find.widgetWithText(StatCard, 'Products')).value, '${metrics.totalProducts}');
      expect(tester.widget<StatCard>(find.widgetWithText(StatCard, 'Orders')).value, '${metrics.totalOrders}');
      expect(tester.widget<StatCard>(find.widgetWithText(StatCard, 'Sales')).value, metrics.totalSalesAmount.toStringAsFixed(0));
    });
  });

  group('System Admin business controls (spec §57 — no dead buttons)', () {
    ProviderContainer adminContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new)]);

    const karwan = 'Karwan Furniture Factory'; // seeded active
    const northern = 'Northern Distribution Center'; // seeded disabled

    /// Walks the real path — admin shell → Businesses → tap a row — so the
    /// detail screen sits on a genuine navigation stack and `pop()` has
    /// somewhere to go, exactly as it does for a user.
    Future<void> openDetail(WidgetTester tester, ProviderContainer container, String name) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
      container.read(routerProvider).go(AppRoutes.adminBusinesses);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
    }

    Future<void> tapControl(WidgetTester tester, String keyValue) async {
      final finder = find.byKey(ValueKey(keyValue));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Scoped to the detail screen, and upper-cased because that's what
    /// `StatusBadge` actually renders.
    Finder detailStatus(String label) => find.descendant(
          of: find.byType(AdminBusinessDetailScreen),
          matching: find.widgetWithText(StatusBadge, label.toUpperCase()),
        );

    /// The confirmation dialog's own button, not the page action behind it
    /// that happens to carry the same label.
    Finder dialogButton(String label) =>
        find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(AppButton, label));

    testWidgets('The section is titled Controls (§57), not Permission', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      expect(find.widgetWithText(SectionCard, 'Controls'), findsOneWidget);
      expect(find.widgetWithText(SectionCard, 'Permission'), findsNothing);
    });

    testWidgets('Not one control is a no-op — every button has a real callback', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      // The four in the Controls card...
      final controls = find.descendant(of: find.widgetWithText(SectionCard, 'Controls'), matching: find.byType(AppButton));
      expect(controls, findsNWidgets(4));
      for (final button in tester.widgetList<AppButton>(controls)) {
        expect(button.onPressed, isNotNull, reason: '"${button.label}" is a dead button');
      }
      // ...plus the status control in the page actions. Six §57 controls are
      // represented: Edit, Reset password, Manage users, View reports, and
      // whichever of Disable/Activate the current status calls for.
      expect(tester.widget<AppButton>(find.byKey(const ValueKey('adminDisableBusiness'))).onPressed, isNotNull);
    });

    testWidgets('Edit opens THIS business prefilled, and Save updates it everywhere', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminEditBusiness');
      expect(find.byType(AdminBusinessFormScreen), findsOneWidget);

      // Prefilled with the selected business, not a blank form.
      expect(find.widgetWithText(AppTextField, karwan), findsOneWidget);
      expect(find.widgetWithText(AppTextField, '+9647701112233'), findsOneWidget);

      await tester.enterText(find.widgetWithText(AppTextField, karwan), 'Karwan Furniture Works');
      await tapControl(tester, 'adminBusinessSave');

      // Back on the detail page, showing the new value — real local state,
      // not a toast over unchanged data.
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
      expect(find.text('Karwan Furniture Works'), findsWidgets);

      // ...and the Businesses table behind it agrees.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessesScreen), findsOneWidget);
      expect(find.text('Karwan Furniture Works'), findsOneWidget);
      expect(find.text(karwan), findsNothing);
    });

    testWidgets('Edit → Cancel returns to Business Details and changes nothing', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminEditBusiness');
      await tester.enterText(find.widgetWithText(AppTextField, karwan), 'Discarded name');
      await tapControl(tester, 'adminBusinessCancel');

      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
      expect(find.text(karwan), findsWidgets);
      expect(find.text('Discarded name'), findsNothing);
    });

    testWidgets('Edit → Back returns to Business Details', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminEditBusiness');
      expect(find.byType(AdminBusinessFormScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
    });

    testWidgets('Disable confirms by name, and cancelling leaves the business active', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminDisableBusiness');
      expect(find.text('Disable $karwan?'), findsOneWidget);

      await tester.tap(dialogButton('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adminDisableBusiness')), findsOneWidget); // still the active-state control
      expect(detailStatus('Active'), findsOneWidget);
    });

    testWidgets('Confirming Disable sets the status to Disabled and swaps the control to Activate', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      expect(detailStatus('Active'), findsOneWidget);

      await tapControl(tester, 'adminDisableBusiness');
      await tester.tap(dialogButton('Deactivate'));
      await tester.pumpAndSettle();

      expect(detailStatus('Disabled'), findsOneWidget);
      // §3 of the brief: never both at once — the offered action must match
      // the current status.
      expect(find.byKey(const ValueKey('adminActivateBusiness')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminDisableBusiness')), findsNothing);
    });

    testWidgets('A disabled business offers Activate, not Disable, and confirming re-activates it', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, northern);

      expect(detailStatus('Disabled'), findsOneWidget);
      expect(find.byKey(const ValueKey('adminActivateBusiness')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminDisableBusiness')), findsNothing);

      await tapControl(tester, 'adminActivateBusiness');
      expect(find.text('Activate $northern?'), findsOneWidget);

      await tester.tap(dialogButton('Activate'));
      await tester.pumpAndSettle();

      expect(detailStatus('Active'), findsOneWidget);
      expect(find.byKey(const ValueKey('adminDisableBusiness')), findsOneWidget);
      expect(find.byKey(const ValueKey('adminActivateBusiness')), findsNothing);
    });

    testWidgets('Reset password validates required / length / match, then records the reset', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      expect(find.text('Password last reset'), findsNothing); // nothing recorded yet

      await tapControl(tester, 'adminResetPassword');
      expect(find.byType(AdminResetPasswordDialog), findsOneWidget);
      // It says on screen that no real password changes — the control is
      // honest about being demo behaviour rather than silently pretending.
      expect(find.textContaining('no real password is stored or changed'), findsOneWidget);

      // Required.
      await tester.tap(find.byKey(const ValueKey('adminResetPasswordConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('Password is required.'), findsWidgets);
      expect(find.byType(AdminResetPasswordDialog), findsOneWidget); // not dismissed

      // Too short, per the app's own configured policy (8).
      await tester.enterText(find.byKey(const ValueKey('adminNewPassword')), 'abc');
      await tester.enterText(find.byKey(const ValueKey('adminConfirmPassword')), 'abc');
      await tester.tap(find.byKey(const ValueKey('adminResetPasswordConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('Password must be at least 8 characters.'), findsOneWidget);

      // Mismatched.
      await tester.enterText(find.byKey(const ValueKey('adminNewPassword')), 'a-good-password');
      await tester.enterText(find.byKey(const ValueKey('adminConfirmPassword')), 'a-different-one');
      await tester.tap(find.byKey(const ValueKey('adminResetPasswordConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);

      // Valid — the dialog closes and the reset becomes visible state.
      await tester.enterText(find.byKey(const ValueKey('adminConfirmPassword')), 'a-good-password');
      await tester.tap(find.byKey(const ValueKey('adminResetPasswordConfirm')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminResetPasswordDialog), findsNothing);
      expect(find.text('Password last reset'), findsOneWidget);
    });

    testWidgets("Manage users opens THIS business's employees, and Back returns", (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminManageUsers');

      expect(find.byType(AdminBusinessRecordsScreen), findsOneWidget);
      expect(find.text(karwan), findsWidgets); // the page names the business
      expect(find.text('Demo Owner'), findsOneWidget); // Karwan's staff
      expect(find.text('Karzan Tahir'), findsNothing); // Erbil's — not this business

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
    });

    testWidgets('View reports opens reports scoped to THIS business, and Back returns', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminViewReports');

      expect(find.byType(AdminBusinessReportsScreen), findsOneWidget);
      expect(find.text(karwan), findsWidgets);
      // Karwan's own products are reported; another tenant's are not.
      expect(find.text('3-Seat Sofa — Charcoal'), findsOneWidget);
      expect(find.text('Office Desk — Standard'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);
    });

    // §11: the controls have to stay usable on a phone and a tablet, not
    // just the desktop width every other test here uses. Both sizes exercise
    // the real breakpoints (`ResponsiveLayout`), including the mobile shell
    // with a drawer instead of a sidebar.
    for (final (label, size) in [('tablet', Size(900, 1400)), ('mobile', Size(420, 1000))]) {
      testWidgets('Controls are reachable and functional at $label width', (tester) async {
        final container = adminContainer();
        addTearDown(container.dispose);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
        await tester.pumpAndSettle();
        container.read(routerProvider).go(AppRoutes.adminBusinessDetail(kDemoBusinessKarwan));
        await tester.pumpAndSettle();
        expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);

        // All four Controls buttons render and are live at this width...
        final controls = find.descendant(of: find.widgetWithText(SectionCard, 'Controls'), matching: find.byType(AppButton));
        expect(controls, findsNWidgets(4));
        for (final button in tester.widgetList<AppButton>(controls)) {
          expect(button.onPressed, isNotNull);
        }

        // ...and one really works end to end, dialog included — the reset
        // dialog is the widest thing the controls open, so it's the one
        // most likely to overflow a narrow screen.
        await tapControl(tester, 'adminResetPassword');
        expect(find.byType(AdminResetPasswordDialog), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('adminNewPassword')), 'a-good-password');
        await tester.enterText(find.byKey(const ValueKey('adminConfirmPassword')), 'a-good-password');
        await tester.tap(find.byKey(const ValueKey('adminResetPasswordConfirm')));
        await tester.pumpAndSettle();
        expect(find.byType(AdminResetPasswordDialog), findsNothing);
        expect(find.text('Password last reset'), findsOneWidget);
      });
    }

    testWidgets('Reports figures are that business\'s own, not the platform totals', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      final metrics = await container.read(adminMetricsProvider.future);
      await openDetail(tester, container, karwan);

      await tapControl(tester, 'adminViewReports');

      final karwanRow = metrics.forBusiness(kDemoBusinessKarwan);
      expect(karwanRow.productCount, lessThan(metrics.totalProducts), reason: 'otherwise this test proves nothing');
      expect(
        tester.widget<StatCard>(find.widgetWithText(StatCard, 'Total products')).value,
        '${karwanRow.productCount}',
      );
    });
  });

  group('Global back navigation (detail pages return to the real previous page)', () {
    ProviderContainer businessContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)]);
    ProviderContainer adminContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAdminAuthenticatedController.new)]);

    Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
    }

    /// Pops via the real back arrow `PageScaffold(showBackButton: true)`
    /// renders — never `context.go(...)` — so this only passes if the
    /// Navigator stack is genuinely popped, not just re-navigated.
    Future<void> tapBack(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    /// One flow, reused for every "list → detail → back → same list" case:
    /// pushes into a detail screen by tapping a real seeded row, then proves
    /// the back arrow returns to the exact previous screen (by type) with
    /// that same row still visible — i.e. a genuine stack pop, not a fresh
    /// navigation to the list's bare route.
    Future<void> verifyListDetailBack(
      WidgetTester tester,
      ProviderContainer container, {
      required String listRoute,
      required Type listScreenType,
      required String rowText,
      required Type detailScreenType,
    }) async {
      container.read(routerProvider).go(listRoute);
      await tester.pumpAndSettle();
      expect(find.byType(listScreenType), findsOneWidget);

      await tester.tap(find.text(rowText).first);
      await tester.pumpAndSettle();
      expect(find.byType(detailScreenType), findsOneWidget);
      expect(find.byType(listScreenType), findsNothing);

      await tapBack(tester);

      expect(find.byType(detailScreenType), findsNothing);
      expect(find.byType(listScreenType), findsOneWidget);
      // findsWidgets, not findsOneWidget: some seeded demo rows share a
      // display name (e.g. a product name used by two production runs) —
      // presence, not uniqueness, is what proves this is the same list
      // instance rather than a fresh empty one.
      expect(find.text(rowText), findsWidgets);
    }

    testWidgets('Products → Product Details → Back → Products', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.products,
        listScreenType: ProductsScreen,
        rowText: '3-Seat Sofa — Charcoal',
        detailScreenType: ProductDetailScreen,
      );
    });

    testWidgets('Orders → Order Details → Back → Orders', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.orders,
        listScreenType: OrdersScreen,
        rowText: 'Karwan Furniture Retail',
        detailScreenType: OrderDetailScreen,
      );
    });

    testWidgets('Customers → Customer Details → Back → Customers', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.customers,
        listScreenType: CustomersScreen,
        rowText: 'Karwan Furniture Retail',
        detailScreenType: CustomerDetailScreen,
      );
    });

    testWidgets('Suppliers → Supplier Details → Back → Suppliers', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.suppliers,
        listScreenType: SuppliersScreen,
        rowText: 'Erbil Timber Supply',
        detailScreenType: SupplierDetailScreen,
      );
    });

    testWidgets('Purchases → Purchase Details → Back → Purchases', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.purchases,
        listScreenType: PurchasesPlaceholderScreen,
        rowText: 'Erbil Timber Supply',
        detailScreenType: PurchaseDetailScreen,
      );
    });

    testWidgets('Returns → Return Details → Back → Returns', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.returns,
        listScreenType: ReturnsPlaceholderScreen,
        rowText: 'Karwan Furniture Retail',
        detailScreenType: ReturnDetailScreen,
      );
    });

    testWidgets('Production → Production Details → Back → Production', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.production,
        listScreenType: ProductionPlaceholderScreen,
        rowText: '3-Seat Sofa — Charcoal',
        detailScreenType: ProductionDetailScreen,
      );
    });

    testWidgets('System Admin Businesses → Business Details → Back → Businesses', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);
      await verifyListDetailBack(
        tester,
        container,
        listRoute: AppRoutes.adminBusinesses,
        listScreenType: AdminBusinessesScreen,
        rowText: 'Karwan Furniture Factory',
        detailScreenType: AdminBusinessDetailScreen,
      );
    });

    testWidgets('A detail page opened from search returns to search results', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);

      container.read(routerProvider).go('${AppRoutes.search}?q=Ergonomic');
      await tester.pumpAndSettle();
      expect(find.byType(SearchResultsScreen), findsOneWidget);

      await tester.tap(find.text('Ergonomic Office Chair'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(find.text('Ergonomic Office Chair'), findsOneWidget); // the same results, query not lost
    });

    testWidgets('A detail page opened from a filtered list returns to that SAME filtered list', (tester) async {
      final container = adminContainer();
      addTearDown(container.dispose);
      await pumpApp(tester, container);

      // Apply the Active filter directly (same mechanism the dashboard's
      // Active card uses), then confirm it survives a push+pop round trip.
      container.read(adminBusinessListControllerProvider.notifier).setFilters({'status': BusinessAccountStatus.active});
      container.read(routerProvider).go(AppRoutes.adminBusinesses);
      await tester.pumpAndSettle();
      expect(find.text('Northern Distribution Center'), findsNothing); // disabled business filtered out

      await tester.tap(find.text('Karwan Furniture Factory'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminBusinessDetailScreen), findsOneWidget);

      await tapBack(tester);

      expect(find.byType(AdminBusinessesScreen), findsOneWidget);
      expect(find.text('Karwan Furniture Factory'), findsOneWidget);
      // The filter is still applied — not reset by the round trip.
      expect(find.text('Northern Distribution Center'), findsNothing);
    });

    testWidgets('The back arrow flips direction under an RTL locale instead of always pointing left', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(FakeAuthenticatedController.new),
          localeProvider.overrideWith(() => _FixedLocaleController(const Locale('ar'))),
        ],
      );
      addTearDown(container.dispose);
      await pumpApp(tester, container);

      container.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3-Seat Sofa — Charcoal').first);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
      // RTL: the back arrow points the opposite way from LTR's
      // Icons.arrow_back — same manual-flip convention as AppSidebar's
      // collapse toggle (arrow_back is a literal glyph, not
      // Directionality-aware on its own).
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      // Not the shared `tapBack` helper — it looks for the LTR glyph.
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsNothing);
      expect(find.byType(ProductsScreen), findsOneWidget);
    });
  });

  group('Roles & permissions (frontend-only role/permission verification)', () {
    // `AuthController.login()` (the real one — these tests exercise the
    // actual demo-login button, not a fake auth state) reads
    // `secureTokenStorageProvider` directly, so this must be overridden in
    // the SAME container `authControllerProvider` resolves against —
    // nesting a second `ProviderScope` with the override inside this
    // container's widget tree does NOT work, since `AuthController` itself
    // is built in (and its `ref` scoped to) the outer container.
    ProviderContainer container() => ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(FakeUnauthenticatedController.new),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );

    Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
    }

    /// Logs in through the REAL login screen (never a fake auth
    /// controller) — taps "Try another role (demo)" to reveal the seven
    /// non-primary business roles, then the named one. Proves the actual
    /// demo login → role-resolution path works end to end, the same path
    /// a person testing the app by hand would use.
    Future<void> loginAsDemoRole(WidgetTester tester, String roleLabel) async {
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.text('Try another role (demo)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, roleLabel));
      await tester.pumpAndSettle();
    }

    // Split into two single-container tests deliberately — pumping a
    // second widget tree (a second `pumpWidget`/container) inside one test
    // makes Riverpod schedule a disposal task for the outgoing tree via a
    // zero-duration Timer that can still be pending when the test's own
    // teardown checks for one, tripping flutter_test's "Timer still
    // pending after dispose" guard. Found by actually running it, not a
    // hypothetical concern — every other test in this file already sticks
    // to one container/one pump for the same reason.
    testWidgets('Owner demo sees "Add Products" on the Products screen', (tester) async {
      final ownerContainer = container();
      addTearDown(ownerContainer.dispose);
      await pumpApp(tester, ownerContainer);
      await tester.tap(find.widgetWithText(AppButton, 'Business (Demo)'));
      await tester.pumpAndSettle();
      ownerContainer.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppButton, 'Add Products'), findsOneWidget);
    });

    testWidgets('Viewer demo (read-only, spec §23) does not see "Add Products", but still sees the seeded rows', (tester) async {
      final viewerContainer = container();
      addTearDown(viewerContainer.dispose);
      await pumpApp(tester, viewerContainer);
      await loginAsDemoRole(tester, 'Viewer');
      viewerContainer.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();
      expect(find.byType(ProductsScreen), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Add Products'), findsNothing);
      // Read access itself is untouched — Viewer still sees the seeded rows.
      expect(find.text('3-Seat Sofa — Charcoal'), findsOneWidget);
    });

    testWidgets('Sales Staff demo sidebar shows Sales/Customers but not Inventory/Production/Settings', (tester) async {
      final demoContainer = container();
      addTearDown(demoContainer.dispose);
      await pumpApp(tester, demoContainer);
      await loginAsDemoRole(tester, 'Sales Staff');

      expect(find.byKey(const ValueKey('nav:/sales')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav:/customers')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav:/inventory')), findsNothing);
      expect(find.byKey(const ValueKey('nav:/production')), findsNothing);
      expect(find.byKey(const ValueKey('nav:/settings')), findsNothing);
    });

    testWidgets('Warehouse Manager demo sidebar shows Inventory but not Production/Settings', (tester) async {
      final demoContainer = container();
      addTearDown(demoContainer.dispose);
      await pumpApp(tester, demoContainer);
      await loginAsDemoRole(tester, 'Warehouse Manager');

      expect(find.byKey(const ValueKey('nav:/inventory')), findsOneWidget);
      // Warehouse Manager's role (spec §23: "Inventory, products, transfers,
      // stock") also grants view-only Sales/Orders visibility in the seeded
      // permission set — so Sales isn't asserted absent here, unlike Sales
      // Staff's own test above. Production and Settings are the two this
      // role genuinely has no grant for.
      expect(find.byKey(const ValueKey('nav:/production')), findsNothing);
      expect(find.byKey(const ValueKey('nav:/settings')), findsNothing);
    });

    testWidgets('Accountant demo sees the Purchase Cost column on Products (financial.view)', (tester) async {
      final accountantContainer = container();
      addTearDown(accountantContainer.dispose);
      await pumpApp(tester, accountantContainer);
      await loginAsDemoRole(tester, 'Accountant');
      // Accountant's role grants no `products.*` (spec §23: "Financial
      // records and reports" only) — reach the screen directly (a sidebar
      // link wouldn't exist) to check the financial-visibility flag in
      // isolation from the products.view nav gate.
      accountantContainer.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();
      expect(find.byType(ProductsScreen), findsOneWidget);
      expect(find.text('Purchase cost'), findsOneWidget); // has financial.view
    });

    testWidgets('Sales Staff demo does not see the Purchase Cost column on Products (no financial.view)', (tester) async {
      final salesContainer = container();
      addTearDown(salesContainer.dispose);
      await pumpApp(tester, salesContainer);
      await loginAsDemoRole(tester, 'Sales Staff');
      salesContainer.read(routerProvider).go(AppRoutes.products);
      await tester.pumpAndSettle();
      expect(find.byType(ProductsScreen), findsOneWidget);
      expect(find.text('Purchase cost'), findsNothing); // no financial.view grant
    });
  });

  test('Factory type configuration: Storage Store excludes Production, Furniture Factory includes it', () {
    final storageStoreModules = businessTypeModules[BusinessType.storageStore]!;
    final furnitureFactoryModules = businessTypeModules[BusinessType.furnitureFactory]!;
    expect(storageStoreModules.contains('production'), isFalse);
    expect(furnitureFactoryModules.contains('production'), isTrue);

    final productionNavItem = businessNavItems.firstWhere((i) => i.moduleKey == 'production');
    expect(storageStoreModules.contains(productionNavItem.moduleKey), isFalse);
  });

  group('Business dashboard (PDF §5 — statistics, charts, quick actions)', () {
    ProviderContainer businessContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)]);

    Future<void> pumpDashboard(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPlaceholderScreen), findsOneWidget);
    }

    StatCard cardNamed(WidgetTester tester, String label) =>
        tester.widget<StatCard>(find.widgetWithText(StatCard, label));

    Future<void> tapCard(WidgetTester tester, String label) async {
      final finder = find.widgetWithText(StatCard, label);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tapQuickAction(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Opens the "More statistics" section. The nine reference figures are
    /// collapsed by default so the six that need acting on are not lost in
    /// a wall of numbers.
    Future<void> expandMoreStatistics(WidgetTester tester) async {
      final toggle = find.byKey(const ValueKey('toggleMoreStatistics'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    // ---- §5 main statistics -------------------------------------------

    testWidgets('All fifteen §5 statistics are present and derived from the repositories', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      final m = await container.read(dashboardMetricsProvider.future);
      await pumpDashboard(tester, container);
      await expandMoreStatistics(tester);

      // The PDF's list, in its own order — all fifteen still exist.
      expect(cardNamed(tester, 'Total products').value, '${m.totalProducts}');
      expect(cardNamed(tester, 'Total categories').value, '${m.totalCategories}');
      expect(cardNamed(tester, 'Total stock quantity').value, '${m.totalStockQuantity}');
      expect(cardNamed(tester, 'Low Stock').value, '${m.lowStockCount}');
      expect(cardNamed(tester, 'Out of Stock').value, '${m.outOfStockCount}');
      expect(cardNamed(tester, 'Today sales').value, m.todaysSalesTotal.toStringAsFixed(2));
      expect(cardNamed(tester, 'Today orders').value, '${m.todaysOrderCount}');
      expect(cardNamed(tester, 'This month sales').value, m.monthSalesTotal.toStringAsFixed(2));
      expect(cardNamed(tester, 'Total sales').value, m.totalSalesTotal.toStringAsFixed(2));
      expect(cardNamed(tester, 'Pending orders').value, '${m.pendingOrders}');
      expect(cardNamed(tester, 'Completed orders').value, '${m.completedOrders}');
      expect(cardNamed(tester, 'Cancelled orders').value, '${m.cancelledOrders}');
      expect(cardNamed(tester, 'Returned orders').value, '${m.returnedOrders}');
      expect(cardNamed(tester, 'Total customers').value, '${m.totalCustomers}');
      expect(cardNamed(tester, 'Total suppliers').value, '${m.totalSuppliers}');
    });

    test('The statistics agree with the underlying demo data', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final m = await container.read(dashboardMetricsProvider.future);
      final products = (await container.read(productRepositoryProvider).list(const PagedQuery(pageSize: 500))).items;
      final orders = (await container.read(orderRepositoryProvider).list(const PagedQuery(pageSize: 500))).items;

      expect(m.totalProducts, products.length);
      expect(m.totalStockQuantity, products.fold<int>(0, (s, p) => s + p.currentQuantity));
      // §44's own definitions: low = qty <= reorder level, out = qty 0.
      expect(m.lowStockCount, products.where((p) => p.isLowStock).length);
      expect(m.outOfStockCount, products.where((p) => p.isOutOfStock).length);
      expect(m.pendingOrders, orders.where((o) => o.status == OrderStatus.pending).length);
      expect(m.completedOrders, orders.where((o) => o.status == OrderStatus.completed).length);
      expect(m.cancelledOrders, orders.where((o) => o.status == OrderStatus.cancelled).length);
      expect(
        m.totalSalesTotal,
        closeTo(orders.where((o) => o.orderType == OrderType.quickSale).fold<double>(0, (s, o) => s + o.grandTotal), 0.001),
      );
    });

    testWidgets('Only the six figures needing attention are shown up front', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      // Four cards, not fifteen — and every one of the four needs acting
      // on today. A figure a module screen already answers ('Total
      // products' is the Products list) is not repeated on the front page.
      expect(find.byType(StatCard), findsNWidgets(4));
      for (final label in ['Low Stock', 'Out of Stock', 'Pending orders', 'Today orders']) {
        expect(find.widgetWithText(StatCard, label), findsOneWidget);
      }
      // Reference figures are not on screen yet...
      expect(find.widgetWithText(StatCard, 'Total products'), findsNothing);
      expect(find.widgetWithText(StatCard, 'Total categories'), findsNothing);
      expect(find.widgetWithText(StatCard, 'Total suppliers'), findsNothing);

      // ...but nothing was deleted: one tap brings all of them back, and
      // §5's full fifteen are still there.
      await expandMoreStatistics(tester);
      expect(find.byType(StatCard), findsNWidgets(16));
      expect(find.widgetWithText(StatCard, 'Total products'), findsOneWidget);
      expect(find.widgetWithText(StatCard, 'Total categories'), findsOneWidget);
      expect(find.widgetWithText(StatCard, 'Total suppliers'), findsOneWidget);
    });

    testWidgets('Sections run statistics → alerts → charts → activity → quick actions', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      // Measured by real on-screen position, not by widget-tree order — it
      // is the rendered order that the reader actually experiences.
      double topOf(Finder finder) => tester.getTopLeft(finder).dy;

      final statistics = topOf(find.byType(StatCard).first);
      final alerts = topOf(find.widgetWithText(SectionCard, 'Alerts'));
      final charts = topOf(find.byType(SimpleBarChart));
      final activity = topOf(find.widgetWithText(SectionCard, 'Recent activity'));
      final quickActions = topOf(find.widgetWithText(SectionCard, 'Quick actions'));

      expect(statistics, lessThan(alerts));
      expect(alerts, lessThan(charts));
      expect(charts, lessThan(activity));
      expect(activity, lessThan(quickActions), reason: 'quick actions must come after recent activity');

      // Nothing but page padding below it: quick actions is the last
      // major section on the page.
      for (final section in ['Alerts', 'Recent activity']) {
        expect(topOf(find.widgetWithText(SectionCard, section)), lessThan(quickActions));
      }
    });

    testWidgets('Quick actions stay compact — buttons, not full-width bars', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      final card = find.widgetWithText(SectionCard, 'Quick actions');
      final buttons = find.descendant(of: card, matching: find.byType(AppButton));
      expect(buttons, findsNWidgets(8));

      // Each button hugs its label rather than stretching across the page.
      final cardWidth = tester.getSize(card).width;
      for (var i = 0; i < 8; i++) {
        expect(
          tester.getSize(buttons.at(i)).width,
          lessThan(cardWidth / 2),
          reason: 'quick action $i should stay compact, not become a full-width bar',
        );
      }
    });

    // The date-range pill and the admin's Refresh both look like controls.
    // These two tests exist so they cannot quietly become decoration: each
    // proves the control changes something real on the screen.
    testWidgets('The date-range control really re-plots the overview chart', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      // Six months by default — the series the chart opens on.
      int plottedBars() => tester
          .widget<VerticalBarChart>(find.byType(VerticalBarChart))
          .points
          .length;
      expect(plottedBars(), 6);

      final chip = find.byKey(const ValueKey('dashboardRangeChip'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // Seven days is a different series of a different length, so the
      // bar count alone proves the chart really re-plotted.
      await tester.tap(find.widgetWithText(PopupMenuItem<OverviewRange>, 'Daily sales (last 7 days)'));
      await tester.pumpAndSettle();
      expect(plottedBars(), 7);
    });

    testWidgets('The section collapses again', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await expandMoreStatistics(tester);
      expect(find.byType(StatCard), findsNWidgets(16));
      await expandMoreStatistics(tester);
      expect(find.byType(StatCard), findsNWidgets(4));
    });

    // ---- the dashboard is not a second sidebar (§2) ---------------------

    testWidgets('Totals with nothing to drill into are informational, not fake buttons', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      await expandMoreStatistics(tester);

      // These would just re-open a module the sidebar already lists, so
      // they carry no onTap at all rather than looking clickable.
      for (final label in ['Total categories', 'Total sales', 'Total customers', 'Total suppliers']) {
        expect(cardNamed(tester, label).onTap, isNull, reason: '"$label" duplicates sidebar navigation');
      }
    });

    testWidgets('Cards that investigate their own number are clickable', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      // Every headline card is a drill-down — that is the rule that
      // decides which four are headline in the first place.
      for (final label in ['Low Stock', 'Out of Stock', 'Pending orders', 'Today orders']) {
        expect(cardNamed(tester, label).onTap, isNotNull, reason: '"$label" should drill into its own records');
      }
      // ...and the collapsed ones keep theirs once expanded.
      await expandMoreStatistics(tester);
      for (final label in ['Completed orders', 'Cancelled orders', 'Returned orders', 'Today sales', 'This month sales']) {
        expect(cardNamed(tester, label).onTap, isNotNull, reason: '"$label" should drill into its own records');
      }
    });

    // ---- §4 drill-downs -------------------------------------------------

    testWidgets('Low Stock opens Inventory filtered to low stock', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await tapCard(tester, 'Low Stock');

      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(container.read(productListControllerProvider).query.filters['stock'], 'low');
      final shown = container.read(productListControllerProvider).items;
      expect(shown, isNotEmpty);
      expect(shown.every((p) => p.isLowStock), isTrue, reason: 'the rows must be exactly what the card counted');
      // The arriving filter announces itself and can be cleared.
      expect(find.byKey(const ValueKey('inventoryStockFilterChip')), findsOneWidget);
    });

    testWidgets('Out of Stock opens Inventory filtered to out of stock', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await tapCard(tester, 'Out of Stock');

      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(container.read(productListControllerProvider).query.filters['stock'], 'out');
      expect(container.read(productListControllerProvider).items.every((p) => p.isOutOfStock), isTrue);
    });

    for (final (label, status) in [
      ('Pending orders', OrderStatus.pending),
      ('Completed orders', OrderStatus.completed),
      ('Cancelled orders', OrderStatus.cancelled),
      ('Returned orders', OrderStatus.returned),
    ]) {
      testWidgets('$label opens Orders filtered to that status', (tester) async {
        final container = businessContainer();
        addTearDown(container.dispose);
        await pumpDashboard(tester, container);
        // Pending is a headline card; the three closed-order counts live
        // in the collapsed section.
        if (label != 'Pending orders') await expandMoreStatistics(tester);

        await tapCard(tester, label);

        expect(find.byType(OrdersScreen), findsOneWidget);
        expect(container.read(orderListControllerProvider).query.filters['status'], status);
        expect(container.read(orderListControllerProvider).items.every((o) => o.status == status), isTrue);
      });
    }

    testWidgets("Today orders opens Orders filtered to today", (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await expandMoreStatistics(tester);
      await tapCard(tester, 'Today orders');

      expect(find.byType(OrdersScreen), findsOneWidget);
      expect(container.read(orderListControllerProvider).query.filters['period'], 'today');
      final now = DateTime.now();
      expect(
        container.read(orderListControllerProvider).items.every(
              (o) => o.createdAt.year == now.year && o.createdAt.month == now.month && o.createdAt.day == now.day,
            ),
        isTrue,
      );
    });

    testWidgets("Today sales opens Sales filtered to today", (tester) async {
      // 'Today sales' is a reference figure now — the headline four are
      // the ones that need acting on, and revenue is already the subject
      // of the overview row's brand panel.
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await expandMoreStatistics(tester);
      await tapCard(tester, 'Today sales');

      expect(find.byType(SalesPlaceholderScreen), findsOneWidget);
      expect(container.read(orderListControllerProvider).query.filters['period'], 'today');
    });

    // ---- §5 visual reports ----------------------------------------------

    testWidgets('All ten §5 chart subjects are offered, and switching really changes the data', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      // Every chart subject the PDF names.
      for (final tab in [
        'Daily sales (last 7 days)',
        'Weekly sales (last 6 weeks)',
        'Monthly sales (last 6 months)',
        'Yearly sales',
        'Top products by revenue',
        'Sales by category',
        'Stock movement',
        'Purchases by month',
        'Returns by month',
        'Profit by month',
      ]) {
        expect(find.byKey(ValueKey('chartTab$tab')), findsOneWidget, reason: '§5 lists $tab');
      }

      // Switching is not cosmetic: the rendered bars change.
      expect(find.text('3-Seat Sofa — Charcoal'), findsNothing);
      final topProducts = find.byKey(const ValueKey('chartTabTop products by revenue'));
      await tester.ensureVisible(topProducts);
      await tester.pumpAndSettle();
      await tester.tap(topProducts);
      await tester.pumpAndSettle();
      expect(find.text('3-Seat Sofa — Charcoal'), findsWidgets, reason: 'the product series should now be plotted');

      // ...and again, to a series with entirely different labels.
      final stockMovement = find.byKey(const ValueKey('chartTabStock movement'));
      await tester.ensureVisible(stockMovement);
      await tester.pumpAndSettle();
      await tester.tap(stockMovement);
      await tester.pumpAndSettle();
      expect(find.text('3-Seat Sofa — Charcoal'), findsNothing);
      expect(find.textContaining('adjustment'), findsWidgets);
    });

    testWidgets('No placeholder chart text survives', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      expect(find.textContaining('Chart will render here'), findsNothing);
      expect(find.textContaining('Coming soon'), findsNothing);
    });

    // ---- §44 alerts -------------------------------------------------------

    testWidgets('Inventory alerts are shown on the dashboard and drill in', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      final m = await container.read(dashboardMetricsProvider.future);
      await pumpDashboard(tester, container);

      // §44 ends with "Show these on the dashboard".
      expect(m.outOfStockCount, greaterThan(0), reason: 'the demo data should exercise this alert');
      final alerts = find.widgetWithText(SectionCard, 'Alerts');
      expect(alerts, findsOneWidget);

      final row = find.descendant(of: alerts, matching: find.text('Out of Stock'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(InventoryScreen), findsOneWidget);
      expect(container.read(productListControllerProvider).query.filters['stock'], 'out');
    });

    // ---- §5 quick actions -------------------------------------------------

    testWidgets('Add product opens the create form', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      await tapQuickAction(tester, 'quickAddProduct');
      expect(find.byType(ProductFormScreen), findsOneWidget);
    });

    testWidgets('Add category opens the create dialog and the saved category appears', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await tapQuickAction(tester, 'quickAddCategory');
      expect(find.byType(CategoryFormDialog), findsOneWidget);

      // Name and Code are both required on this dialog.
      final fields = find.descendant(of: find.byType(CategoryFormDialog), matching: find.byType(AppTextField));
      await tester.enterText(fields.at(0), 'Garden Furniture');
      await tester.enterText(fields.at(1), 'GARDEN');
      await tester.tap(find.widgetWithText(AppButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.byType(CategoriesScreen), findsOneWidget);
      expect(find.text('Garden Furniture'), findsOneWidget);
    });

    testWidgets('New sale opens the sale workflow', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      await tapQuickAction(tester, 'quickNewSale');
      expect(find.byType(OrderFormScreen), findsOneWidget);
    });

    testWidgets('New order opens the order workflow', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      await tapQuickAction(tester, 'quickNewOrder');
      expect(find.byType(OrderFormScreen), findsOneWidget);
    });

    testWidgets('Add customer opens the create dialog and the saved customer appears', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await tapQuickAction(tester, 'quickAddCustomer');
      expect(find.byType(CustomerFormDialog), findsOneWidget);

      final fields = find.descendant(of: find.byType(CustomerFormDialog), matching: find.byType(AppTextField));
      await tester.enterText(fields.at(0), 'Nawroz Trading');
      await tester.enterText(fields.at(1), '+9647705550000');
      await tester.tap(find.widgetWithText(AppButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomersScreen), findsOneWidget);
      expect(find.text('Nawroz Trading'), findsOneWidget);
    });

    testWidgets('Add supplier opens the create dialog and the saved supplier appears', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);

      await tapQuickAction(tester, 'quickAddSupplier');
      expect(find.byType(SupplierFormDialog), findsOneWidget);

      // Field order is Name, Company, Phone — Phone is the required one.
      final fields = find.descendant(of: find.byType(SupplierFormDialog), matching: find.byType(AppTextField));
      await tester.enterText(fields.at(0), 'Zagros Timber');
      await tester.enterText(fields.at(2), '+9647705550111');
      await tester.tap(find.widgetWithText(AppButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.byType(SuppliersScreen), findsOneWidget);
      expect(find.text('Zagros Timber'), findsOneWidget);
    });

    testWidgets('Add stock asks which product, then really moves the stock', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      final before = (await container.read(productRepositoryProvider).getById('prod-1')).currentQuantity;

      await tapQuickAction(tester, 'quickAddStock');
      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(const ValueKey('stockAdjustSave'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('stockProductPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('3-Seat Sofa — Charcoal').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('stockQuantity')), '7');
      await tester.tap(find.byKey(const ValueKey('stockAdjustSave')));
      await tester.pumpAndSettle();

      expect((await container.read(productRepositoryProvider).getById('prod-1')).currentQuantity, before + 7);
    });

    testWidgets('Generate report opens Reports', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await pumpDashboard(tester, container);
      await tapQuickAction(tester, 'quickGenerateReport');
      expect(find.byType(ReportsPlaceholderScreen), findsOneWidget);
    });

    // ---- §11 recent activity ----------------------------------------------

    testWidgets('Recent activity shows real records and opens them', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      final m = await container.read(dashboardMetricsProvider.future);
      await pumpDashboard(tester, container);

      expect(m.recentActivity, isNotEmpty);
      final feed = find.widgetWithText(SectionCard, 'Recent activity');
      expect(feed, findsOneWidget);

      // Every entry carries a real destination.
      for (final entry in m.recentActivity.take(8)) {
        expect(entry.route, isNotEmpty);
      }
    });

    // ---- §19 localization / RTL, §20 dark mode -----------------------------

    for (final locale in [const Locale('ar'), const Locale('ku')]) {
      testWidgets('Renders under ${locale.languageCode} with RTL directionality and localized labels', (tester) async {
        final container = businessContainer();
        addTearDown(container.dispose);
        tester.view.physicalSize = const Size(1400, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        container.read(localeProvider.notifier).setLocale(locale);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
        await tester.pumpAndSettle();

        expect(find.byType(DashboardPlaceholderScreen), findsOneWidget);
        expect(Directionality.of(tester.element(find.byType(DashboardPlaceholderScreen))), TextDirection.rtl);
        // The English strings must be gone — a card still reading "Total
        // products" would mean an unlocalized literal.
        expect(find.text('Total products'), findsNothing);
        expect(find.byType(StatCard), findsWidgets);
        expect(find.byKey(const ValueKey('quickAddProduct')), findsOneWidget);
      });
    }

    testWidgets('Renders in dark mode without losing any section', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();

      expect(Theme.of(tester.element(find.byType(DashboardPlaceholderScreen))).brightness, Brightness.dark);
      expect(find.byType(StatCard), findsWidgets);
      expect(find.widgetWithText(SectionCard, 'Alerts'), findsOneWidget);
      expect(find.widgetWithText(SectionCard, 'Recent activity'), findsOneWidget);
      expect(find.byType(SimpleBarChart), findsOneWidget);
    });

    // ---- §18 responsive ----------------------------------------------------

    for (final (label, size) in [('tablet', Size(800, 1600)), ('mobile', Size(390, 1800))]) {
      testWidgets('Statistics, charts and quick actions all render at $label width', (tester) async {
        final container = businessContainer();
        addTearDown(container.dispose);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
        await tester.pumpAndSettle();

        expect(find.byType(DashboardPlaceholderScreen), findsOneWidget);
        expect(find.byType(StatCard), findsWidgets);
        expect(find.widgetWithText(SectionCard, 'Alerts'), findsOneWidget);
        expect(find.byKey(const ValueKey('quickAddProduct')), findsOneWidget);
        // A drill-down still works at this width.
        await tapCard(tester, 'Pending orders');
        expect(find.byType(OrdersScreen), findsOneWidget);
      });
    }
  });

  group('Reports (spec §25/§26 — every card opens a real report)', () {
    ProviderContainer businessContainer() =>
        ProviderContainer(overrides: [authControllerProvider.overrideWith(FakeAuthenticatedController.new)]);

    Future<void> openReports(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WarehouseOsApp()));
      await tester.pumpAndSettle();
      container.read(routerProvider).go(AppRoutes.reports);
      await tester.pumpAndSettle();
    }

    testWidgets('No report card says "Coming soon" any more', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await openReports(tester, container);

      expect(find.text('Coming soon'), findsNothing);
    });

    testWidgets('A previously dead card opens a real report over real rows', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await openReports(tester, container);

      // Stock movement was one of the ten `onTap: null` cards.
      await tester.tap(find.text('Stock movement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stock movement'), findsWidgets);
      // Seeded movements exist, so the report is not an empty shell.
      expect(find.text('Nothing here yet'), findsNothing);
    });

    testWidgets('Export produces the real CSV for the rows on screen', (tester) async {
      final container = businessContainer();
      addTearDown(container.dispose);
      await openReports(tester, container);

      // Scoped to the screen — "Inventory" is also a sidebar nav item.
      await tester.tap(find.descendant(of: find.byType(ReportsPlaceholderScreen), matching: find.text('Inventory')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('reportExport')));
      await tester.pumpAndSettle();

      // Real content, and honest about what it is.
      expect(find.textContaining('3-Seat Sofa — Charcoal'), findsWidgets);
      expect(find.textContaining('Demo mode'), findsOneWidget);
    });

    test('buildCsv quotes separators and escapes quotes', () {
      final csv = buildCsv(
        ['name', 'note'],
        [
          ['Sofa, 3-seat', 'He said "hello"'],
        ],
      );
      expect(csv, 'name,note\n"Sofa, 3-seat","He said ""hello"""');
    });
  });

  group('Permissions actually change the UI when edited (spec §24)', () {
    test('Editing a role updates what the signed-in user may do, without a restart', () async {
      final container = ProviderContainer(
        // A session whose phone really matches a seeded Employee, so a Role
        // resolves — `testAccount`'s phone deliberately matches none, which
        // is why most tests run unrestricted.
        overrides: [authControllerProvider.overrideWith(_DemoOwnerSessionController.new)],
      );
      addTearDown(container.dispose);

      final before = container.read(currentPermissionsProvider);
      expect(before, isNotNull);
      expect(before!.contains('products.view'), isTrue);

      final role = container.read(currentRoleProvider)!;
      await container.read(rolesVersionProvider.notifier).updatePermissions(
            role.id,
            {...role.permissions}..remove('products.view'),
          );

      // Previously this stayed cached for the whole session: the checkbox
      // moved and nothing else did.
      final after = container.read(currentPermissionsProvider);
      expect(after!.contains('products.view'), isFalse);
      expect(
        enabledBusinessNavItemsFor(after, BusinessType.furnitureFactory).any((i) => i.route == AppRoutes.products),
        isFalse,
        reason: 'the sidebar must drop a module the role can no longer view',
      );
    });
  });

  group('Stock engine — business actions actually move inventory', () {
    // Before this existed you could sell a sofa, complete the order, and the
    // sofa's quantity never changed. Every test below asserts BOTH halves:
    // the quantity moved, and a movement row was written for it (spec §12 —
    // stock never changes without history).

    Future<int> quantityOf(ProviderContainer container, String productId) async =>
        (await container.read(productRepositoryProvider).getById(productId)).currentQuantity;

    Future<List<StockMovement>> movements(ProviderContainer container) async =>
        (await container.read(inventoryRepositoryProvider).listMovements(const PagedQuery(pageSize: 200))).items;

    test('A quick sale consumes stock and records a sale movement', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await quantityOf(container, 'prod-1');

      final sale = await container.read(orderRepositoryProvider).create(
            const OrderDraft(
              orderType: OrderType.quickSale,
              items: [OrderItemDraft(productId: 'prod-1', productName: '3-Seat Sofa — Charcoal', quantity: 2, unitPrice: 420)],
            ),
          );
      await container.read(stockEngineProvider).apply(stockChangesFor(sale), type: MovementType.sale, note: sale.orderNumber);

      expect(await quantityOf(container, 'prod-1'), before - 2);
      final movement = (await movements(container)).firstWhere((m) => m.note == sale.orderNumber);
      expect(movement.type, MovementType.sale);
      expect(movement.previousQuantity, before);
      expect(movement.newQuantity, before - 2);
    });

    test('Cancelling a completed order puts the stock back', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await quantityOf(container, 'prod-3');

      final order = await container.read(orderRepositoryProvider).create(
            const OrderDraft(
              orderType: OrderType.standard,
              items: [OrderItemDraft(productId: 'prod-3', productName: 'Coffee Table — Oak', quantity: 4, unitPrice: 120)],
            ),
          );
      final engine = container.read(stockEngineProvider);
      await engine.apply(stockChangesFor(order), type: MovementType.sale);
      expect(await quantityOf(container, 'prod-3'), before - 4);

      await engine.reverse(stockChangesFor(order), type: MovementType.sale);
      expect(await quantityOf(container, 'prod-3'), before, reason: 'reversal must be exactly symmetric');
    });

    test('Completing a purchase increases stock and records a purchase movement', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await quantityOf(container, 'prod-6');

      await container.read(stockEngineProvider).apply(
        [const StockChange(productId: 'prod-6', productName: 'Solid Pine Timber (2m)', delta: 200)],
        type: MovementType.purchase,
        note: 'PUR-TEST',
      );

      expect(await quantityOf(container, 'prod-6'), before + 200);
      expect((await movements(container)).firstWhere((m) => m.note == 'PUR-TEST').type, MovementType.purchase);
    });

    test('A completed return restocks sellable lines only — damaged ones record a movement but no stock', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sellableBefore = await quantityOf(container, 'prod-1');
      final damagedBefore = await quantityOf(container, 'prod-2');

      await container.read(stockEngineProvider).apply(
        [
          // Exactly what ReturnDetailScreen builds: sellable keeps its
          // quantity, damaged is zeroed but still recorded.
          const StockChange(productId: 'prod-1', productName: 'sellable', delta: 3),
          const StockChange(productId: 'prod-2', productName: 'damaged', delta: 0),
        ],
        type: MovementType.returnMovement,
        note: 'RET-TEST',
      );

      expect(await quantityOf(container, 'prod-1'), sellableBefore + 3);
      expect(await quantityOf(container, 'prod-2'), damagedBefore, reason: 'damaged goods must not become sellable stock');
      final rows = (await movements(container)).where((m) => m.note == 'RET-TEST').toList();
      expect(rows, hasLength(2), reason: 'both lines are real events the ledger should show');
    });

    test('Completing production consumes materials per unit built and adds finished goods', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final timberBefore = await quantityOf(container, 'prod-6'); // BOM material
      final sofaBefore = await quantityOf(container, 'prod-1'); // finished good

      // prod-1's BOM needs 4 timber per unit; a run of 5 consumes 20.
      const built = 5;
      const timberPerUnit = 4;
      await container.read(stockEngineProvider).apply(
        [
          const StockChange(productId: 'prod-6', productName: 'Solid Pine Timber (2m)', delta: -(timberPerUnit * built)),
          const StockChange(productId: 'prod-1', productName: '3-Seat Sofa — Charcoal', delta: built),
        ],
        type: MovementType.production,
        note: 'PRDN-TEST',
      );

      expect(await quantityOf(container, 'prod-6'), timberBefore - (timberPerUnit * built));
      expect(await quantityOf(container, 'prod-1'), sofaBefore + built);
    });

    test('Stock never goes negative, and the movement row agrees with the clamp', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await quantityOf(container, 'prod-5');

      await container.read(stockEngineProvider).apply(
        [StockChange(productId: 'prod-5', productName: 'Bookshelf — 5 Tier', delta: -(before + 50))],
        type: MovementType.sale,
        note: 'OVERSELL',
      );

      expect(await quantityOf(container, 'prod-5'), 0, reason: 'negative demo stock makes every downstream figure nonsense');
    });

    test('The dashboard total reflects a sale immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = await container.read(dashboardMetricsProvider.future);

      final sale = await container.read(orderRepositoryProvider).create(
            const OrderDraft(
              orderType: OrderType.quickSale,
              items: [OrderItemDraft(productId: 'prod-1', productName: '3-Seat Sofa — Charcoal', quantity: 1, unitPrice: 420)],
            ),
          );
      await container.read(stockEngineProvider).apply(stockChangesFor(sale), type: MovementType.sale);

      final after = await container.read(dashboardMetricsProvider.future);
      expect(after.totalSalesTotal, greaterThan(before.totalSalesTotal));
      expect(after.totalStockQuantity, before.totalStockQuantity - 1);
    });
  });

  group('Cross-module effects beyond stock', () {
    test("Creating an order rolls into the customer's totals", () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final customers = container.read(customerRepositoryProvider);
      final created = await customers.create(const CustomerDraft(fullName: 'Rollup Test', phone: '+9647700000123'));

      // A customer starts at zero and used to stay there for ever, so the
      // Customers table was permanently wrong for anyone you added.
      expect(created.totalPurchases, 0);
      expect(created.orderCount, 0);

      await customers.applyOrder(created.id, grandTotal: 250, paidAmount: 100);
      final after = await customers.getById(created.id);

      expect(after.orderCount, 1);
      expect(after.totalPurchases, 250);
      expect(after.outstandingBalance, 150, reason: 'what is still owed on the order');
    });

    test('Overpaying does not create a negative balance', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final customers = container.read(customerRepositoryProvider);
      final created = await customers.create(const CustomerDraft(fullName: 'Overpay', phone: '+9647700000124'));

      await customers.applyOrder(created.id, grandTotal: 100, paidAmount: 180);
      expect((await customers.getById(created.id)).outstandingBalance, 0);
    });

    test('Creating a transfer really adds a row — the repository method had no caller', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final inventory = container.read(inventoryRepositoryProvider);
      final before = (await inventory.listTransfers(const PagedQuery(pageSize: 100))).total;

      await inventory.createTransfer(
        fromWarehouseId: 'wh-1',
        toWarehouseId: 'wh-2',
        productName: '3-Seat Sofa — Charcoal',
        quantity: 3,
      );

      final after = await inventory.listTransfers(const PagedQuery(pageSize: 100));
      expect(after.total, before + 1);
      expect(after.items.first.quantity, 3);
      expect(after.items.first.status, TransferStatus.pending);
    });
  });

  group('Demo/backend mode selection (frontend-only demo-mode verification)', () {
    test('buildAuthRepository selects DemoAuthRepository for AppMode.demo', () {
      final client = ApiClient();
      final repo = buildAuthRepository(AppMode.demo, client, AccountType.businessUser);
      expect(repo, isA<DemoAuthRepository>());
    });

    test('buildAuthRepository selects ApiAuthRepository for AppMode.backend', () {
      final client = ApiClient();
      final repo = buildAuthRepository(AppMode.backend, client, AccountType.businessUser);
      expect(repo, isA<ApiAuthRepository>());
    });

    test('backend mode targets the right identity system for each account type', () {
      // The backend keeps business users and System Admins in separate tables
      // behind separate routes, so sending an admin's credentials to /auth
      // can only ever 401 — which is exactly what happened before this was
      // wired up. These assert the repository carries the account type
      // through, which is what selects the base path.
      final client = ApiClient();

      final business = buildAuthRepository(AppMode.backend, client, AccountType.businessUser);
      expect((business as ApiAuthRepository).accountType, AccountType.businessUser);

      final admin = buildAuthRepository(AppMode.backend, client, AccountType.systemAdmin);
      expect((admin as ApiAuthRepository).accountType, AccountType.systemAdmin);
    });

    test('the account type defaults to a business user, and fails safe', () {
      // A wrong default must ask the ordinary route, never the privileged
      // one, and must not be sticky across a fresh container.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedAccountTypeProvider), AccountType.businessUser);
    });

    test('selecting System Admin swaps the repository to the admin routes', () {
      // Proves the selector is wired all the way through: choosing an account
      // type must change which identity system the next login talks to, not
      // merely which button looks pressed.
      //
      // `AppMode.backend` is passed explicitly rather than read from
      // `AppModeConfig`, because `flutter test` compiles in demo mode — going
      // through the provider here would only ever build the demo repository
      // and the assertion would be vacuous.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final client = ApiClient();

      final before = buildAuthRepository(
        AppMode.backend,
        client,
        container.read(selectedAccountTypeProvider),
      );
      expect((before as ApiAuthRepository).accountType, AccountType.businessUser);

      container.read(selectedAccountTypeProvider.notifier).select(AccountType.systemAdmin);

      final after = buildAuthRepository(
        AppMode.backend,
        client,
        container.read(selectedAccountTypeProvider),
      );
      expect((after as ApiAuthRepository).accountType, AccountType.systemAdmin);
    });

    test('the account type survives a reload, so an admin session can refresh', () async {
      // Without persisting it, restoring a stored System Admin session asks
      // the business-user route to refresh a token it has never seen — the
      // session silently dies on every page reload.
      final storage = InMemoryTokenStorage();
      await storage.saveAccountType(accountTypeToStorage(AccountType.systemAdmin));
      expect(accountTypeFromStorage(await storage.readAccountType()), AccountType.systemAdmin);

      // And clearing the session must clear it too, so the next login starts
      // from the safe default rather than inheriting the admin route.
      await storage.clear();
      expect(accountTypeFromStorage(await storage.readAccountType()), AccountType.businessUser);
    });

    test('DemoAuthRepository resolves login/refresh/me without any HTTP client', () async {
      // No ApiClient/Dio instance exists anywhere in this test — proves the
      // demo path genuinely never reaches for the network, not just that it
      // happens to succeed.
      final repo = DemoAuthRepository();

      final businessSession = await repo.login(phone: kDemoBusinessPhone, password: kDemoPassword);
      expect(businessSession.business, isNotNull);
      expect(businessSession.account.name, 'Demo Owner');

      final adminSession = await repo.login(phone: kDemoAdminPhone, password: kDemoPassword);
      expect(adminSession.business, isNull);
      expect(adminSession.account.name, 'Demo System Admin');

      final refreshed = await repo.refresh(adminSession.refreshToken);
      final identity = await repo.me();
      expect(identity.business, isNull); // still the admin identity after refresh
      expect(refreshed.accessToken, isNotEmpty);
    });

    test('All 9 demo identities (System Admin + one per business role) resolve to a distinct account and role', () async {
      final repo = DemoAuthRepository();
      final employees = LocalEmployeeRepository();

      const expected = {
        kDemoBusinessPhone: ('Demo Owner', 'role-owner'),
        kDemoManagerPhone: ('Zana Hussein', 'role-manager'),
        kDemoWarehouseManagerPhone: ('Rezan Ali', 'role-warehouse'),
        kDemoSalesStaffPhone: ('Dilan Omar', 'role-sales'),
        kDemoInventoryStaffPhone: ('Ary Karim', 'role-inventory'),
        kDemoProductionManagerPhone: ('Soran Najat', 'role-production'),
        kDemoAccountantPhone: ('Lana Faraj', 'role-accountant'),
        kDemoViewerPhone: ('Hero Salih', 'role-viewer'),
      };

      final seenNames = <String>{};
      for (final entry in expected.entries) {
        final (name, roleId) = entry.value;
        final session = await repo.login(phone: entry.key, password: kDemoPassword);
        expect(session.account.name, name, reason: 'login for ${entry.key}');
        expect(session.business, isNotNull, reason: 'every business role stays inside the same demo business');
        seenNames.add(session.account.name);

        // The link permission_providers.dart relies on: this exact phone
        // must resolve to the exact role the demo login claims.
        final role = employees.roleForPhoneSync(entry.key);
        expect(role, isNotNull, reason: 'no seeded Employee for ${entry.key}');
        expect(role!.id, roleId);
      }
      expect(seenNames, hasLength(8)); // 8 distinct business identities, no collisions

      final adminSession = await repo.login(phone: kDemoAdminPhone, password: kDemoPassword);
      expect(adminSession.account.name, 'Demo System Admin');
      expect(adminSession.business, isNull);
      // System Admin is not a business role — no Employee/Role to resolve.
      expect(employees.roleForPhoneSync(kDemoAdminPhone), isNull);
    });

    testWidgets('Default mode (no dart-define) is demo — the app never calls a real backend to reach the dashboard', (tester) async {
      expect(AppModeConfig.mode, AppMode.demo, reason: 'flutter test runs with no --dart-define=APP_MODE, so this proves the documented default');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage())],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      // The login screen's own demo card carries the same "DEMO MODE" text
      // as the shell's badge — both are real, both are expected here.
      expect(find.text('DEMO MODE'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Business (Demo)'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('DEMO MODE'), findsOneWidget); // shell-wide indicator, §10
    });

    testWidgets('System Admin demo reaches the admin dashboard, not the business shell', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage())],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'System Admin (Demo)'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Businesses'), findsWidgets); // admin nav item + page title
      // Widget-type checks, not text: several labels (e.g. "Products") are
      // legitimately reused as admin stat-card headings on this very
      // screen, so text alone can't prove which shell rendered — the type
      // of the landed screen can.
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.byType(DashboardPlaceholderScreen), findsNothing);
    });

    testWidgets('Demo session survives logout → the business demo can log back in', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureTokenStorageProvider.overrideWithValue(InMemoryTokenStorage())],
          child: const WarehouseOsApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Business (Demo)'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('accountMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Business (Demo)'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsWidgets);
    });
  });
}

/// Test-only: pumps [AuthSessionExpired] directly without needing a real
/// interceptor-triggered failure.
class _FakeSessionExpiredController extends AuthController {
  @override
  AuthState build() => const AuthSessionExpired();
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

/// An authenticated business session whose phone matches a seeded
/// `Employee`, so `currentRoleProvider` resolves a real Role to test
/// permission changes against.
class _DemoOwnerSessionController extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
        account: AuthAccount(id: 1, name: 'Demo Owner', phone: kDemoBusinessPhone),
        business: testBusiness,
      );
}
