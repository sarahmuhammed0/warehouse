import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/activity_history/activity_history_screen.dart';
import '../features/admin/admin_businesses_screen.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/auth/login_placeholder_screen.dart';
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

/// Routing foundation (§23). Three separate trees, on purpose:
///  - **Public** (`AppRoutes.login`) — no shell at all.
///  - **Business application** — one `ShellRoute` wrapping every module in
///    `businessNavItems`, rendered inside `AppShell`.
///  - **System Admin** (§56/§57) — a second, independent `ShellRoute` with
///    its own nav set, never sharing a shell instance with the business
///    app (a System Admin session and a business session are never the
///    same UI context, matching the architecture's tenant-isolation
///    principle at the routing level too).
///
/// No auth/permission guard exists yet (§27) — `redirect` is where Phase 2
/// adds one, without moving a single route. See the commented example
/// below; it is intentionally inert (returns `null`, meaning "no
/// redirect") so Phase 1 imposes no login requirement.
final appRouter = GoRouter(
  initialLocation: AppRoutes.dashboard,
  redirect: (context, state) {
    // Phase 2 extension point — not active yet:
    //
    // final isAuthenticated = ref.read(authStateProvider).isAuthenticated;
    // final isPublicRoute = state.matchedLocation == AppRoutes.login;
    // if (!isAuthenticated && !isPublicRoute) return AppRoutes.login;
    // if (isAuthenticated && isPublicRoute) return AppRoutes.dashboard;
    return null;
  },
  routes: [
    GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPlaceholderScreen()),
    GoRoute(path: AppRoutes.systemStatus, builder: (context, state) => const SystemStatusScreen()),

    ShellRoute(
      builder: (context, state, child) =>
          AppShell(navItems: businessNavItems, brandLabel: 'Warehouse OS', child: child),
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
