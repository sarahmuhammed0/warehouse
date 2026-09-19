import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';

/// One sidebar entry. `permissionKey` is deliberately present but unused in
/// Phase 1 — architecture §8/§9: the backend is the only authority on what
/// a user may see, and the UI must never be the security boundary. Phase 2
/// wires a permission-aware sidebar by filtering this list against the
/// signed-in user's granted permissions; nothing about the sidebar widget
/// itself needs to change when that happens — see `AppSidebar`.
@immutable
class NavItem {
  const NavItem({
    required this.route,
    required this.icon,
    required this.labelBuilder,
    this.permissionKey,
    this.moduleKey,
  });

  final String route;
  final IconData icon;
  final String Function(AppLocalizations l10n) labelBuilder;

  /// e.g. "products.view" (architecture §9's `{module}.{action}` shape).
  /// Not checked against anything yet — see class doc.
  final String? permissionKey;

  /// Key into `businessTypeModules` (spec §33's factory-type module
  /// configuration) — separate from [permissionKey] since a module can be
  /// enabled/disabled per business type independently of any user's
  /// individual permission grants within an enabled module.
  final String? moduleKey;
}

/// The business application's sidebar (specification §6).
final List<NavItem> businessNavItems = [
  NavItem(
    route: AppRoutes.dashboard,
    icon: Icons.dashboard_outlined,
    labelBuilder: (l10n) => l10n.navDashboard,
    permissionKey: 'dashboard.view',
    moduleKey: 'dashboard',
  ),
  NavItem(
    route: AppRoutes.products,
    icon: Icons.inventory_2_outlined,
    labelBuilder: (l10n) => l10n.navProducts,
    permissionKey: 'products.view',
    moduleKey: 'products',
  ),
  NavItem(
    route: AppRoutes.categories,
    icon: Icons.category_outlined,
    labelBuilder: (l10n) => l10n.navCategories,
    permissionKey: 'categories.view',
    moduleKey: 'categories',
  ),
  NavItem(
    route: AppRoutes.inventory,
    icon: Icons.warehouse_outlined,
    labelBuilder: (l10n) => l10n.navInventory,
    permissionKey: 'inventory.view',
    moduleKey: 'inventory',
  ),
  NavItem(
    route: AppRoutes.sales,
    icon: Icons.point_of_sale_outlined,
    labelBuilder: (l10n) => l10n.navSales,
    permissionKey: 'sales.view',
    moduleKey: 'sales',
  ),
  NavItem(
    route: AppRoutes.orders,
    icon: Icons.receipt_long_outlined,
    labelBuilder: (l10n) => l10n.navOrders,
    permissionKey: 'orders.view',
    moduleKey: 'orders',
  ),
  NavItem(
    route: AppRoutes.customers,
    icon: Icons.people_outline,
    labelBuilder: (l10n) => l10n.navCustomers,
    permissionKey: 'customers.view',
    moduleKey: 'customers',
  ),
  NavItem(
    route: AppRoutes.suppliers,
    icon: Icons.local_shipping_outlined,
    labelBuilder: (l10n) => l10n.navSuppliers,
    permissionKey: 'suppliers.view',
    moduleKey: 'suppliers',
  ),
  NavItem(
    route: AppRoutes.purchases,
    icon: Icons.shopping_cart_outlined,
    labelBuilder: (l10n) => l10n.navPurchases,
    permissionKey: 'purchases.view',
    moduleKey: 'purchases',
  ),
  NavItem(
    route: AppRoutes.returns,
    icon: Icons.assignment_return_outlined,
    labelBuilder: (l10n) => l10n.navReturns,
    permissionKey: 'returns.view',
    moduleKey: 'returns',
  ),
  NavItem(
    route: AppRoutes.production,
    icon: Icons.precision_manufacturing_outlined,
    labelBuilder: (l10n) => l10n.navProduction,
    permissionKey: 'production.view',
    moduleKey: 'production',
  ),
  NavItem(
    route: AppRoutes.employees,
    icon: Icons.badge_outlined,
    labelBuilder: (l10n) => l10n.navEmployees,
    permissionKey: 'users.view',
    moduleKey: 'employees',
  ),
  NavItem(
    route: AppRoutes.reports,
    icon: Icons.bar_chart_outlined,
    labelBuilder: (l10n) => l10n.navReports,
    permissionKey: 'reports.view',
    moduleKey: 'reports',
  ),
  NavItem(
    route: AppRoutes.documents,
    icon: Icons.description_outlined,
    labelBuilder: (l10n) => l10n.navDocuments,
    permissionKey: 'documents.view',
    moduleKey: 'documents',
  ),
  NavItem(
    route: AppRoutes.activityHistory,
    icon: Icons.history_outlined,
    labelBuilder: (l10n) => l10n.navActivityHistory,
    permissionKey: 'audit.view',
    moduleKey: 'activityHistory',
  ),
  NavItem(
    route: AppRoutes.settings,
    icon: Icons.settings_outlined,
    labelBuilder: (l10n) => l10n.navSettings,
    permissionKey: 'settings.manage',
    moduleKey: 'settings',
  ),
];

/// The System Admin area's sidebar (specification §56/§57) — intentionally
/// small; the admin console's own detail screens are a later phase.
final List<NavItem> adminNavItems = [
  NavItem(
    route: AppRoutes.adminDashboard,
    icon: Icons.admin_panel_settings_outlined,
    labelBuilder: (l10n) => l10n.adminNavDashboard,
  ),
  NavItem(
    route: AppRoutes.adminBusinesses,
    icon: Icons.apartment_outlined,
    labelBuilder: (l10n) => l10n.adminNavBusinesses,
  ),
];
