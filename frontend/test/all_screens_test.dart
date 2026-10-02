// Every screen in the application, mounted in backend mode.
//
// There is no browser automation in this environment, so this is the closest
// honest equivalent to clicking through all of it: the real app, the real
// router, the real widget tree, every repository on its real Api*
// implementation, behind one stubbed HTTP layer that answers every endpoint.
//
// What each case asserts:
//   1. the route renders — no exception reached the framework, and
//   2. the screen is not showing an error, and
//   3. where the screen displays server data, that the FIXTURE's value is on
//      screen — so a screen that renders beautifully from nothing still fails.
//
// (3) is the part that matters. A screen that throws is obvious the moment
// anyone opens it. A screen that quietly shows an empty table because the
// wiring reads `name` where the server sends `label` looks completely fine.

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';

import 'fakes/api_backed_app.dart';

void main() {
  /// A route that must render, and the text that proves it rendered real data.
  /// `expect: null` means "this screen shows no server data of its own" — a
  /// form, or a hub of links — so rendering without throwing is the whole test.
  ///
  /// Seventeen constants in `AppRoutes` are deliberately absent from this list,
  /// because they are not routes: nothing registers them with the router and
  /// nothing in the app links to them, so navigating to one shows the 404 page.
  /// They name capabilities that are reached another way — the Settings
  /// sections are one screen with an internal sidebar, transfers and locations
  /// are tabs inside Inventory, notifications is the header bell, adding staff
  /// is a dialog. They were found by this sweep after "Page not found" was
  /// added to `failureText`; without that line every one of them passed while
  /// rendering nothing but the 404 page. Registering or removing them is a
  /// product decision, not a test one.
  const businessScreens = <({String route, String name, String? expect})>[
    (route: AppRoutes.dashboard, name: 'Dashboard', expect: null),

    (route: AppRoutes.products, name: 'Products', expect: fixtureProductName),
    (route: AppRoutes.productNew, name: 'Product — new', expect: null),
    (route: '/products/5', name: 'Product — detail', expect: fixtureProductName),
    (route: '/products/5/edit', name: 'Product — edit', expect: fixtureProductName),
    (route: '/products/5/history', name: 'Product — history', expect: fixtureProductName),

    (route: AppRoutes.categories, name: 'Categories', expect: fixtureCategoryName),

    (route: AppRoutes.inventory, name: 'Inventory', expect: fixtureProductName),

    (route: AppRoutes.sales, name: 'Sales', expect: fixtureSaleNumber),
    (route: AppRoutes.saleNew, name: 'Sale — new', expect: null),
    (route: AppRoutes.orders, name: 'Orders', expect: fixtureOrderNumber),
    (route: AppRoutes.orderNew, name: 'Order — new', expect: null),
    (route: '/orders/21', name: 'Order — detail', expect: fixtureOrderNumber),

    (route: AppRoutes.customers, name: 'Customers', expect: fixtureCustomerName),
    (route: '/customers/7', name: 'Customer — detail', expect: fixtureCustomerName),
    (route: AppRoutes.suppliers, name: 'Suppliers', expect: fixtureSupplierName),
    (route: '/suppliers/4', name: 'Supplier — detail', expect: fixtureSupplierName),

    (route: AppRoutes.purchases, name: 'Purchases', expect: fixturePurchaseNumber),
    (route: AppRoutes.purchaseNew, name: 'Purchase — new', expect: null),
    (route: '/purchases/31', name: 'Purchase — detail', expect: fixturePurchaseNumber),

    (route: AppRoutes.returns, name: 'Returns', expect: fixtureReturnNumber),
    (route: AppRoutes.returnNew, name: 'Return — new', expect: null),
    (route: '/returns/12', name: 'Return — detail', expect: fixtureReturnNumber),

    (route: AppRoutes.production, name: 'Production', expect: fixtureRunNumber),
    (route: AppRoutes.productionNew, name: 'Production — new', expect: null),
    (route: '/production/6', name: 'Production — detail', expect: fixtureRunNumber),

    (route: AppRoutes.employees, name: 'Staff', expect: fixtureStaffName),
    (route: AppRoutes.roles, name: 'Roles & permissions', expect: 'Warehouse Manager'),

    (route: AppRoutes.reports, name: 'Reports', expect: null),

    (route: AppRoutes.documents, name: 'Documents', expect: fixtureOrderNumber),

    (route: AppRoutes.activityHistory, name: 'Activity history', expect: fixtureAuditDescription),
    (route: AppRoutes.search, name: 'Search', expect: null),
    (route: AppRoutes.systemStatus, name: 'System status', expect: null),

    // Settings opens on its General section; the business name, custom fields
    // and the rest each need their sidebar entry clicked, which is what
    // screen_actions_test.dart does.
    (route: AppRoutes.settings, name: 'Settings', expect: null),
  ];

  const adminScreens = <({String route, String name, String? expect})>[
    (route: AppRoutes.adminDashboard, name: 'Admin — dashboard', expect: null),
    (route: AppRoutes.adminBusinesses, name: 'Admin — businesses', expect: fixtureBusinessName),
    (route: AppRoutes.adminBusinessCreate, name: 'Admin — business create', expect: null),
    (route: '/admin/businesses/1', name: 'Admin — business detail', expect: fixtureBusinessName),
    (route: '/admin/businesses/1/edit', name: 'Admin — business edit', expect: fixtureBusinessName),
    (route: '/admin/businesses/1/reports', name: 'Admin — business reports', expect: null),
    (route: AppRoutes.adminRegistrations, name: 'Admin — registrations', expect: null),
    (route: AppRoutes.adminEmployees, name: 'Admin — staff overview', expect: null),
    (route: '/admin/employees/1', name: 'Admin — staff for a business', expect: fixtureStaffName),
    (route: AppRoutes.adminProducts, name: 'Admin — products overview', expect: null),
    (route: '/admin/products/1', name: 'Admin — products for a business', expect: fixtureProductName),
    (route: AppRoutes.adminOrders, name: 'Admin — orders overview', expect: null),
    (route: '/admin/orders/1', name: 'Admin — orders for a business', expect: fixtureOrderNumber),
    (route: AppRoutes.adminSales, name: 'Admin — sales overview', expect: null),
    (route: '/admin/sales/1', name: 'Admin — sales for a business', expect: null),
  ];

  /// Text the app shows when something went wrong. If any of these is on
  /// screen the route "rendered", which is exactly the false pass this sweep
  /// exists to avoid.
  const failureText = [
    'Something went wrong',
    'Unable to load',
    'Request failed',
    'No stub for',
    'NOT_STUBBED',
    // The one that was missing on the first run of this sweep, and the reason
    // it reported green for routes that do not exist: a route declared in
    // AppRoutes but never registered in the router renders the 404 page, which
    // contains none of the strings above. Every route with no data expectation
    // therefore passed while showing nothing but "Page not found."
    'Page not found',
  ];

  Future<void> check(
    WidgetTester tester,
    ({String route, String name, String? expect}) screen, {
    bool asAdmin = false,
  }) async {
    final app = apiBackedApp(asAdmin: asAdmin);
    addTearDown(app.container.dispose);

    await pumpAppAt(tester, app.container, screen.route);

    expect(
      tester.takeException(),
      isNull,
      reason: '${screen.name} (${screen.route}) threw while rendering',
    );

    for (final failure in failureText) {
      expect(
        find.textContaining(failure, findRichText: true),
        findsNothing,
        reason: '${screen.name} (${screen.route}) is showing "$failure"',
      );
    }

    if (screen.expect != null) {
      expect(
        find.textContaining(screen.expect!, findRichText: true),
        findsWidgets,
        reason:
            '${screen.name} (${screen.route}) rendered without showing the '
            'server\'s "${screen.expect}" — the screen works, the data did not reach it',
      );
    }
  }

  group('Every business screen renders the server\'s data', () {
    for (final screen in businessScreens) {
      testWidgets('${screen.name}  ${screen.route}', (tester) => check(tester, screen));
    }
  });

  group('Every System Admin screen renders the server\'s data', () {
    for (final screen in adminScreens) {
      testWidgets('${screen.name}  ${screen.route}', (tester) => check(tester, screen, asAdmin: true));
    }
  });

}
