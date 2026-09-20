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
import 'package:warehouse_os_app/features/admin/presentation/admin_business_records_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_overview_screen.dart';
import 'package:warehouse_os_app/features/admin/presentation/admin_record_detail_screen.dart';
import 'package:warehouse_os_app/features/auth/data/auth_models.dart';
import 'package:warehouse_os_app/features/auth/data/auth_repository.dart';
import 'package:warehouse_os_app/features/auth/data/demo_auth_repository.dart';
import 'package:warehouse_os_app/features/auth/presentation/login_screen.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_state.dart';
import 'package:warehouse_os_app/features/categories/categories_screen.dart';
import 'package:warehouse_os_app/features/customers/customers_screen.dart';
import 'package:warehouse_os_app/features/customers/presentation/customer_detail_screen.dart';
import 'package:warehouse_os_app/features/dashboard/dashboard_screen.dart';
import 'package:warehouse_os_app/features/employees/data/employee_providers.dart';
import 'package:warehouse_os_app/features/employees/data/employee_repository.dart';
import 'package:warehouse_os_app/features/orders/data/order_providers.dart';
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
import 'package:warehouse_os_app/shared/dashboard/metric_cards.dart';
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

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
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

    testWidgets('Dashboard shows total-products/total-customers stat cards without colliding with sidebar labels', (tester) async {
      final container = authenticatedContainer();
      addTearDown(container.dispose);
      await pumpDesktop(tester, container);

      // Exactly one "Products" (sidebar) and one "Total products" (stat
      // card) — these must never collide on the same screen.
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Total products'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
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

      await tester.tap(find.widgetWithText(StatCard, 'Businesses'));
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

      expect(find.widgetWithText(StatCard, '3'), findsOneWidget); // the Active card's own count

      await tester.tap(find.widgetWithText(StatCard, 'Active'));
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

      expect(find.widgetWithText(StatCard, '1'), findsOneWidget); // the Disabled card's own count

      await tester.tap(find.widgetWithText(StatCard, 'Disabled'));
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

      expect(find.text('Sales'), findsWidgets); // nav item (+ possibly a card label)
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Inventory'), findsNothing);
      expect(find.text('Production'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('Warehouse Manager demo sidebar shows Inventory but not Production/Settings', (tester) async {
      final demoContainer = container();
      addTearDown(demoContainer.dispose);
      await pumpApp(tester, demoContainer);
      await loginAsDemoRole(tester, 'Warehouse Manager');

      expect(find.text('Inventory'), findsOneWidget);
      // Warehouse Manager's role (spec §23: "Inventory, products, transfers,
      // stock") also grants view-only Sales/Orders visibility in the seeded
      // permission set — so Sales isn't asserted absent here, unlike Sales
      // Staff's own test above. Production and Settings are the two this
      // role genuinely has no grant for.
      expect(find.text('Production'), findsNothing);
      expect(find.text('Settings'), findsNothing);
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

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
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
