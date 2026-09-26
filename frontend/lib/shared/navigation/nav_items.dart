import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../features/auth/presentation/providers/permission_providers.dart';
import '../../features/settings/data/business_type_config.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';

/// One sidebar entry. `permissionKey` was originally present but unused —
/// see [enabledBusinessNavItems] below and
/// `features/auth/presentation/providers/permission_providers.dart` for
/// where it's now consulted. Still only a UI convenience, never the
/// security boundary (architecture §8/§9): the backend is the only real
/// authority on what a user may do; this only controls what the UI shows.
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

  /// e.g. "products.view" (architecture §9's `{module}.{action}` shape,
  /// matching `PermissionCatalog.key`) — see class doc for where it's used.
  final String? permissionKey;

  /// Key into `businessTypeModules` (spec §33's factory-type module
  /// configuration) — separate from [permissionKey] since a module can be
  /// enabled/disabled per business type independently of any user's
  /// individual permission grants within an enabled module.
  final String? moduleKey;
}

/// The product's own name, as the platform-level shell and its dashboard
/// both display it. Not an l10n string: a product name is not translated,
/// and `appName` is the older generic label the login screen still uses.
const String platformBrandName = 'FactoryOS';

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
    permissionKey: 'settings.edit',
    moduleKey: 'settings',
  ),
];

/// The System Admin area's navigation (specification §56/§57).
///
/// The four record overviews are cross-tenant summaries — "which business
/// has how many products", not one business's product table — so they
/// belong to the platform shell and never open a tenant's operational
/// screens. They were always routes with real screens behind them; before,
/// the only door in was a dashboard card.
final List<NavItem> adminNavItems = [
  NavItem(
    route: AppRoutes.adminDashboard,
    icon: Icons.space_dashboard_outlined,
    labelBuilder: (l10n) => l10n.adminNavDashboard,
  ),
  NavItem(
    route: AppRoutes.adminBusinesses,
    icon: Icons.apartment_outlined,
    labelBuilder: (l10n) => l10n.adminNavBusinesses,
  ),
  NavItem(
    route: AppRoutes.adminRegistrations,
    icon: Icons.how_to_reg_outlined,
    labelBuilder: (l10n) => l10n.navRegistrations,
  ),
  NavItem(
    route: AppRoutes.adminEmployees,
    icon: Icons.people_outline,
    labelBuilder: (l10n) => l10n.navEmployees,
  ),
  NavItem(
    route: AppRoutes.adminProducts,
    icon: Icons.inventory_2_outlined,
    labelBuilder: (l10n) => l10n.navProducts,
  ),
  NavItem(
    route: AppRoutes.adminOrders,
    icon: Icons.receipt_long_outlined,
    labelBuilder: (l10n) => l10n.navOrders,
  ),
  NavItem(
    route: AppRoutes.adminSales,
    icon: Icons.point_of_sale_outlined,
    labelBuilder: (l10n) => l10n.navSales,
  ),
];

/// §24: once authenticated, the shell re-brands itself with the real
/// business's name instead of the generic product name — the "future
/// business-specific experience" hook, using real data only (never a
/// placeholder business name pretending to be real).
String businessBrandLabel(WidgetRef ref) {
  final state = ref.watch(authControllerProvider);
  if (state is AuthAuthenticated && state.business != null) {
    return state.business!.name;
  }
  return 'Warehouse OS';
}

/// Factory type configuration (spec §33) — filters the sidebar down to the
/// modules `businessTypeModules` enables for the demo business's current
/// type, e.g. a Storage Store never sees Production. Data-driven (a map
/// lookup), not a widget-level `if (businessType == ...)`.
List<NavItem> enabledBusinessNavItems(WidgetRef ref) {
  return enabledBusinessNavItemsFor(
    ref.watch(currentPermissionsProvider),
    ref.watch(businessTypeProvider),
  );
}

/// The filtering itself, with its two inputs passed in rather than watched.
///
/// Split out so the rule can be tested directly — "revoking products.view
/// removes Products from the sidebar" is a statement about this function,
/// and proving it shouldn't require pumping a whole app.
List<NavItem> enabledBusinessNavItemsFor(Set<String>? permissions, BusinessType type) {
  final enabled = businessTypeModules[type] ?? const <String>{};
  // Two independent filters, both narrowing-only, safe to AND together:
  // moduleKey (is this module relevant to this business TYPE at all —
  // spec §33) and permissionKey (can THIS USER view it — spec §24). A
  // `null` permission set (no linked demo Employee — see
  // permission_providers.dart) never hides anything on its own.
  return businessNavItems.where((item) {
    final moduleAllowed = item.moduleKey == null || enabled.contains(item.moduleKey);
    final permissionAllowed = item.permissionKey == null || _hasNavPermission(permissions, item.permissionKey!);
    return moduleAllowed && permissionAllowed;
  }).toList();
}

/// `NavItem.permissionKey` is already a full `"module.action"` string
/// (e.g. `"products.view"`), not separate module/action parts, so this
/// splits it once rather than reusing `hasPermission`'s two-argument form.
bool _hasNavPermission(Set<String>? permissions, String permissionKey) {
  if (permissions == null) return true;
  return permissions.contains(permissionKey);
}

/// How the shell splits one module list across its two navigation surfaces
/// (§7/§8's app-shell redesign): a labelled pill bar across the header for
/// the destinations a business opens all day, and an icon rail down the
/// side for everything else.
///
/// The split is a partition, never a copy. Every enabled module appears in
/// exactly one of the two, so there is no second menu offering the same
/// destination twice — which is the thing §8 actually forbids, as opposed
/// to having two *surfaces*, which the reference designs themselves use.
///
/// [primaryNavRoutes] is ordered by how often a module is opened rather
/// than by the sidebar's old top-to-bottom order, and the header keeps that
/// order. Anything not listed — and anything listed but filtered out by
/// role or business type — falls through to the rail untouched.
const List<String> primaryNavRoutes = [
  AppRoutes.dashboard,
  AppRoutes.products,
  AppRoutes.inventory,
  AppRoutes.sales,
  AppRoutes.orders,
  AppRoutes.reports,
];

/// The System Admin area is small enough that every destination fits in
/// the header, so its rail carries only the shell's own controls.
const List<String> adminPrimaryNavRoutes = [
  AppRoutes.adminDashboard,
  AppRoutes.adminBusinesses,
  AppRoutes.adminRegistrations,
  AppRoutes.adminEmployees,
  AppRoutes.adminProducts,
  AppRoutes.adminOrders,
  AppRoutes.adminSales,
];

/// ({header: [...], rail: [...]}) for an already-filtered module list.
({List<NavItem> primary, List<NavItem> secondary}) splitNavItems(
  List<NavItem> items, {
  List<String> primaryRoutes = primaryNavRoutes,
}) {
  final byRoute = {for (final item in items) item.route: item};
  final primary = [
    for (final route in primaryRoutes)
      if (byRoute.containsKey(route)) byRoute[route]!,
  ];
  final chosen = primary.map((i) => i.route).toSet();
  final secondary = [
    for (final item in items)
      if (!chosen.contains(item.route)) item,
  ];
  return (primary: primary, secondary: secondary);
}
