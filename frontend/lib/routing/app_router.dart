import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activity_history/activity_history_screen.dart';
import '../features/admin/admin_businesses_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/admin/presentation/admin_business_detail_screen.dart';
import '../features/admin/presentation/admin_business_form_screen.dart';
import '../features/admin/presentation/admin_business_records_screen.dart';
import '../features/admin/presentation/admin_business_reports_screen.dart';
import '../features/admin/presentation/admin_metric.dart';
import '../features/admin/presentation/admin_overview_screen.dart';
import '../features/admin/presentation/admin_record_detail_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/providers/auth_controller.dart';
import '../features/auth/presentation/providers/auth_state.dart';
import '../features/categories/categories_screen.dart' show CategoriesScreen;
import '../features/customers/customers_screen.dart';
import '../features/customers/presentation/customer_detail_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/employees/presentation/roles_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/orders/data/order_models.dart';
import '../features/orders/orders_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/orders/presentation/order_form_screen.dart';
import '../features/production/presentation/production_detail_screen.dart';
import '../features/production/presentation/production_form_screen.dart';
import '../features/production/production_screen.dart';
import '../features/products/presentation/product_detail_screen.dart';
import '../features/products/presentation/product_form_screen.dart';
import '../features/products/presentation/product_history_screen.dart';
import '../features/products/products_screen.dart';
import '../features/purchases/presentation/purchase_detail_screen.dart';
import '../features/purchases/presentation/purchase_form_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/returns/presentation/return_detail_screen.dart';
import '../features/returns/presentation/return_form_screen.dart';
import '../features/returns/returns_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/search/presentation/search_results_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/suppliers/presentation/supplier_detail_screen.dart';
import '../features/suppliers/suppliers_screen.dart';
import '../features/system_status/presentation/system_status_screen.dart';
import '../shared/layout/app_shell.dart';
import '../shared/navigation/nav_items.dart';
import 'app_routes.dart';

/// Routing foundation (§23), guards activated in Phase 2 (§21). Three
/// separate trees, on purpose:
///  - **Public** (`AppRoutes.login`) — no shell at all.
///  - **Business application** — one `ShellRoute` wrapping every module in
///    `businessNavItems`, rendered inside `AppShell`.
///  - **System Admin** (§56/§57) — a second, independent `ShellRoute` with
///    its own nav set, never sharing a shell instance with the business
///    app.
///
/// IMPORTANT (§21's own warning, worth repeating here): everything in this
/// file is UX/navigation convenience — it stops a signed-out user from
/// *seeing* a business screen's empty shell, nothing more. It is not, and
/// cannot be, the security boundary; every route's actual data comes from
/// backend endpoints that independently re-check `req.auth` on every
/// request (architecture §10). A bug here would be a bad user experience,
/// not a data breach — the reverse must never be true.
///
/// `routerProvider` (not a top-level constant) because the redirect logic
/// needs to read `authControllerProvider` — this is the extension point
/// Phase 1 left inert for exactly this purpose.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: _GoRouterRefreshNotifier(ref),
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
      GoRoute(path: AppRoutes.systemStatus, builder: (context, state) => const SystemStatusScreen()),

      ShellRoute(
        builder: (context, state, child) => AppShell.business(child: child),
        routes: [
          GoRoute(path: AppRoutes.dashboard, builder: (context, state) => const DashboardPlaceholderScreen()),
          GoRoute(path: AppRoutes.products, builder: (context, state) => const ProductsScreen()),
          GoRoute(path: AppRoutes.productNew, builder: (context, state) => const ProductFormScreen()),
          GoRoute(
            path: '/products/:id/history',
            builder: (context, state) => ProductHistoryScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products/:id/edit',
            builder: (context, state) => ProductFormScreen(productId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.categories, builder: (context, state) => const CategoriesScreen()),
          GoRoute(path: AppRoutes.inventory, builder: (context, state) => const InventoryScreen()),
          GoRoute(path: AppRoutes.sales, builder: (context, state) => const SalesPlaceholderScreen()),
          GoRoute(path: AppRoutes.saleNew, builder: (context, state) => const OrderFormScreen(orderType: OrderType.quickSale)),
          GoRoute(path: AppRoutes.orders, builder: (context, state) => const OrdersScreen()),
          GoRoute(path: '/orders/new', builder: (context, state) => const OrderFormScreen(orderType: OrderType.standard)),
          GoRoute(
            path: '/orders/:id',
            builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.customers, builder: (context, state) => const CustomersScreen()),
          GoRoute(
            path: '/customers/:id',
            builder: (context, state) => CustomerDetailScreen(customerId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.suppliers, builder: (context, state) => const SuppliersScreen()),
          GoRoute(
            path: '/suppliers/:id',
            builder: (context, state) => SupplierDetailScreen(supplierId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.purchases, builder: (context, state) => const PurchasesPlaceholderScreen()),
          GoRoute(path: AppRoutes.purchaseNew, builder: (context, state) => const PurchaseFormScreen()),
          GoRoute(
            path: '/purchases/:id',
            builder: (context, state) => PurchaseDetailScreen(purchaseId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.returns, builder: (context, state) => const ReturnsPlaceholderScreen()),
          GoRoute(
            path: AppRoutes.returnNew,
            builder: (context, state) => ReturnFormScreen(orderId: state.uri.queryParameters['orderId']),
          ),
          GoRoute(
            path: '/returns/:id',
            builder: (context, state) => ReturnDetailScreen(returnId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.production, builder: (context, state) => const ProductionPlaceholderScreen()),
          GoRoute(path: AppRoutes.productionNew, builder: (context, state) => const ProductionFormScreen()),
          GoRoute(
            path: '/production/:id',
            builder: (context, state) => ProductionDetailScreen(productionId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.employees, builder: (context, state) => const EmployeesPlaceholderScreen()),
          GoRoute(path: AppRoutes.roles, builder: (context, state) => const RolesScreen()),
          GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsPlaceholderScreen()),
          GoRoute(path: AppRoutes.documents, builder: (context, state) => const DocumentsPlaceholderScreen()),
          GoRoute(
            path: AppRoutes.activityHistory,
            builder: (context, state) => const ActivityHistoryPlaceholderScreen(),
          ),
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPlaceholderScreen()),
          GoRoute(
            path: AppRoutes.search,
            builder: (context, state) => SearchResultsScreen(query: state.uri.queryParameters['q'] ?? ''),
          ),
        ],
      ),

      ShellRoute(
        // The platform-level shell. Same design system as the business
        // side, but it says what it is and wears a shield rather than a
        // business initial — §3's "System Admin should remain visually
        // distinguishable as the platform-level administration area".
        builder: (context, state, child) => AppShell(
          navItems: adminNavItems,
          primaryRoutes: adminPrimaryNavRoutes,
          brandLabel: platformBrandName,
          brandSubtitle: 'System Admin',
          brandIcon: Icons.shield_outlined,
          showSearch: false,
          child: child,
        ),
        routes: [
          GoRoute(path: AppRoutes.adminDashboard, builder: (context, state) => const AdminDashboardScreen()),
          GoRoute(path: AppRoutes.adminBusinesses, builder: (context, state) => const AdminBusinessesScreen()),
          GoRoute(
            path: '/admin/businesses/:id',
            builder: (context, state) => AdminBusinessDetailScreen(businessId: state.pathParameters['id']!),
          ),
          // §57's Edit and View reports controls. Both carry the business id
          // in the path, so the screen they open can only ever act on the
          // business the admin was looking at — there is no ambient
          // "selected business" state that could point somewhere else.
          GoRoute(
            path: '/admin/businesses/:id/edit',
            builder: (context, state) => AdminBusinessFormScreen(businessId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/businesses/:id/reports',
            builder: (context, state) => AdminBusinessReportsScreen(businessId: state.pathParameters['id']!),
          ),
          // The three-level drill-down, one identical branch per metric:
          // overview (all businesses) → one business's records → one record.
          // Each level is its own route so every step is a real push and the
          // back arrow pops exactly one level.
          ..._adminMetricRoutes(),
        ],
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: Center(child: Text('Page not found.')),
    ),
  );
});

/// The System Admin drill-down's routes, generated from [AdminMetric] so
/// Employees/Products/Orders/Sales cannot drift apart: each metric gets the
/// same three levels, pointing at the same three generic screens. Adding a
/// fifth drillable statistic later means adding an enum value, not four
/// more route blocks.
List<GoRoute> _adminMetricRoutes() {
  return [
    for (final metric in AdminMetric.values) ...[
      GoRoute(
        path: metric.overviewRoute,
        builder: (context, state) => AdminOverviewScreen(metric: metric),
      ),
      GoRoute(
        path: '${metric.overviewRoute}/:businessId',
        builder: (context, state) => AdminBusinessRecordsScreen(metric: metric, businessId: state.pathParameters['businessId']!),
      ),
      GoRoute(
        path: '${metric.overviewRoute}/:businessId/:recordId',
        builder: (context, state) => AdminRecordDetailScreen(
          metric: metric,
          businessId: state.pathParameters['businessId']!,
          recordId: state.pathParameters['recordId']!,
        ),
      ),
    ],
  ];
}

String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final location = state.matchedLocation;
  final isAdminRoute = location.startsWith('/admin');
  final isPublicRoute = location == AppRoutes.login || location == AppRoutes.systemStatus;

  // Session restore hasn't resolved yet — don't redirect either way. The
  // router's `initialLocation` is the login screen specifically so this
  // brief window never shows protected business data (see this file's top
  // doc comment).
  if (authState is AuthInitial) return null;

  if (authState is! AuthAuthenticated) {
    return isPublicRoute ? null : AppRoutes.login;
  }

  // Which shell an authenticated session belongs to is a real signal the
  // session itself already carries: `business == null` is exactly how
  // `AuthSession`/`AuthIdentity` mark a System Admin identity (see
  // auth_models.dart's own doc comment) — never a separate flag that could
  // drift out of sync with it. Before the frontend-only demo mode
  // (docs/frontend-demo-mode.md) added a System Admin *demo* login, Phase
  // 2's Flutter app only ever authenticated business users in practice, so
  // this branch was previously unreachable rather than absent — nothing
  // about real backend-mode behavior changes here.
  final isAdminSession = authState.business == null;

  if (isPublicRoute) {
    return isAdminSession ? AppRoutes.adminDashboard : AppRoutes.dashboard;
  }
  if (isAdminRoute && !isAdminSession) return AppRoutes.dashboard;
  // A System Admin session stays inside the admin shell, with no exceptions.
  // An earlier revision whitelisted /products, /orders, /sales and
  // /employees so the dashboard's stat cards could open the business app's
  // own operational tables — that is exactly what the three-level drill-down
  // replaces: the admin now reaches those records through
  // `/admin/<metric>/<businessId>`, having explicitly chosen a business, and
  // never lands in a warehouse's operational table by tapping a platform
  // statistic.
  if (!isAdminRoute && isAdminSession) return AppRoutes.adminDashboard;
  return null;
}

/// Bridges Riverpod state changes into the `Listenable` go_router expects
/// for `refreshListenable` — without this, a login/logout wouldn't cause
/// `redirect` to re-run until some unrelated navigation event happened to
/// trigger it.
class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}
