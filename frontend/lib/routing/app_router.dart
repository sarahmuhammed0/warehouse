import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activity_history/activity_history_screen.dart';
import '../features/admin/admin_businesses_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/providers/auth_controller.dart';
import '../features/auth/presentation/providers/auth_state.dart';
import '../features/categories/categories_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/production/production_screen.dart';
import '../features/products/products_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/returns/returns_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/settings/settings_screen.dart';
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
        builder: (context, state, child) => AppShell(
          navItems: businessNavItems,
          brandLabel: _businessBrandLabel(ref),
          child: child,
        ),
        routes: [
          GoRoute(path: AppRoutes.dashboard, builder: (context, state) => const DashboardPlaceholderScreen()),
          GoRoute(path: AppRoutes.products, builder: (context, state) => const ProductsPlaceholderScreen()),
          GoRoute(path: AppRoutes.categories, builder: (context, state) => const CategoriesPlaceholderScreen()),
          GoRoute(path: AppRoutes.inventory, builder: (context, state) => const InventoryPlaceholderScreen()),
          GoRoute(path: AppRoutes.sales, builder: (context, state) => const SalesPlaceholderScreen()),
          GoRoute(path: AppRoutes.orders, builder: (context, state) => const OrdersPlaceholderScreen()),
          GoRoute(path: AppRoutes.customers, builder: (context, state) => const CustomersPlaceholderScreen()),
          GoRoute(path: AppRoutes.suppliers, builder: (context, state) => const SuppliersPlaceholderScreen()),
          GoRoute(path: AppRoutes.purchases, builder: (context, state) => const PurchasesPlaceholderScreen()),
          GoRoute(path: AppRoutes.returns, builder: (context, state) => const ReturnsPlaceholderScreen()),
          GoRoute(path: AppRoutes.production, builder: (context, state) => const ProductionPlaceholderScreen()),
          GoRoute(path: AppRoutes.employees, builder: (context, state) => const EmployeesPlaceholderScreen()),
          GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsPlaceholderScreen()),
          GoRoute(path: AppRoutes.documents, builder: (context, state) => const DocumentsPlaceholderScreen()),
          GoRoute(
            path: AppRoutes.activityHistory,
            builder: (context, state) => const ActivityHistoryPlaceholderScreen(),
          ),
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPlaceholderScreen()),
        ],
      ),

      ShellRoute(
        builder: (context, state, child) =>
            AppShell(navItems: adminNavItems, brandLabel: 'System Admin', child: child),
        routes: [
          GoRoute(path: AppRoutes.adminDashboard, builder: (context, state) => const AdminDashboardScreen()),
          GoRoute(path: AppRoutes.adminBusinesses, builder: (context, state) => const AdminBusinessesScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: Center(child: Text('Page not found.')),
    ),
  );
});

/// §24: once authenticated, the shell re-brands itself with the real
/// business's name instead of the generic product name — the "future
/// business-specific experience" hook, using real data only (never a
/// placeholder business name pretending to be real).
String _businessBrandLabel(Ref ref) {
  final state = ref.watch(authControllerProvider);
  if (state is AuthAuthenticated && state.business != null) {
    return state.business!.name;
  }
  return 'Warehouse OS';
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

  final isAuthenticated = authState is AuthAuthenticated;

  if (!isAuthenticated) {
    return isPublicRoute ? null : AppRoutes.login;
  }

  // Authenticated. Phase 2's Flutter UI only ever authenticates business
  // users (see auth_controller.dart) — there is no Flutter System Admin
  // login yet, so any authenticated session reaching an admin route is
  // necessarily a business user and must be turned away (§21: "must not
  // accidentally inherit arbitrary business-user access" — the same rule
  // in reverse).
  if (isAdminRoute) return AppRoutes.dashboard;
  if (location == AppRoutes.login) return AppRoutes.dashboard;
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
