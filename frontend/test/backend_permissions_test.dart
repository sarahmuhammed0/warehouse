// What a backend-mode session is allowed to SEE.
//
// Until this pass, `currentPermissionsProvider` resolved only in demo mode —
// it matched a demo login's phone to a seeded employee. A real session had no
// role at all, so it resolved to null, which `hasPermission` treats as
// unrestricted: every nav item was offered to every role, and the server
// refused on the click.
//
// Now the server resolves the role and hands it over with the session, so
// these tests pin the two halves that could silently go wrong: that a session
// carrying a role is actually restricted by it, and that the three nav keys
// with no endpoint behind them still resolve.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_os_app/features/auth/data/auth_models.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_controller.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/auth_state.dart';
import 'package:warehouse_os_app/features/auth/presentation/providers/permission_providers.dart';
import 'package:warehouse_os_app/features/settings/data/business_type_config.dart';
import 'package:warehouse_os_app/routing/app_routes.dart';
import 'package:warehouse_os_app/shared/navigation/nav_items.dart';

/// An authenticated state holding exactly the grants a server would send.
class _FixedAuth extends AuthController {
  _FixedAuth(this._permissions);
  final Set<String>? _permissions;

  @override
  AuthState build() => AuthAuthenticated(
    account: const AuthAccount(id: 1, name: 'Lana Aziz', phone: '+9647500000012'),
    business: const AuthBusiness(
      id: 1,
      name: 'Karwan Furniture Factory',
      businessType: 'furniture_factory',
      logoUrl: null,
      currency: 'IQD',
      language: 'en',
      timezone: 'UTC',
      status: 'active',
    ),
    role: _permissions == null
        ? null
        : AuthRole(id: 12, name: 'Sales Staff', isSystemRole: true, permissions: _permissions),
  );
}

Set<String>? permissionsFor(Set<String>? sessionGrants) {
  final container = ProviderContainer(
    overrides: [authControllerProvider.overrideWith(() => _FixedAuth(sessionGrants))],
  );
  addTearDown(container.dispose);
  return container.read(currentPermissionsProvider);
}

void main() {
  group('A backend session is restricted by the role the server gave it', () {
    test('the session\'s grants become the permission set', () {
      expect(permissionsFor({'orders.view', 'sales.view'}), {'orders.view', 'sales.view'});
    });

    test('a session with no role resolves to null, which means unrestricted', () {
      // A System Admin belongs to no business and holds no business-scoped
      // role. Their own area is gated by account type, not by this.
      expect(permissionsFor(null), isNull);
    });

    test('an empty grant list restricts everything — it is not read as "no role"', () {
      // The distinction that matters: null means "nothing to restrict
      // against", an empty SET means "this role grants nothing". Collapsing
      // the two would hand a stripped role the whole application.
      final permissions = permissionsFor(<String>{});
      expect(permissions, isNotNull);
      expect(permissions, isEmpty);
      expect(hasPermission(permissions, 'products', 'view'), isFalse);
    });
  });

  group('The sidebar offers only what the server will allow', () {
    List<String> routesFor(Set<String> permissions) =>
        enabledBusinessNavItemsFor(permissions, BusinessType.furnitureFactory)
            .map((item) => item.route)
            .toList();

    test('Sales Staff gets no Reports, no Users and no Activity History', () {
      // The real grant list the seeded Sales Staff role holds, plus the two
      // navigation keys the server derives for it.
      final routes = routesFor({
        'sales.view', 'sales.create', 'sales.edit',
        'orders.view', 'orders.create', 'orders.edit',
        'customers.view', 'products.view',
        'dashboard.view', 'documents.view',
      });

      expect(routes, contains(AppRoutes.sales));
      expect(routes, contains(AppRoutes.documents));
      expect(routes, contains(AppRoutes.dashboard));
      expect(routes, isNot(contains(AppRoutes.reports)));
      expect(routes, isNot(contains(AppRoutes.employees)));
      expect(routes, isNot(contains(AppRoutes.activityHistory)));
      expect(routes, isNot(contains(AppRoutes.settings)));
    });

    test('an owner gets everything the business type enables', () {
      final routes = routesFor({
        for (final module in PermissionCatalogModules.all)
          for (final action in ['view', 'create', 'edit', 'delete']) '$module.$action',
        'dashboard.view', 'documents.view', 'audit.view',
      });

      expect(routes, contains(AppRoutes.reports));
      expect(routes, contains(AppRoutes.employees));
      expect(routes, contains(AppRoutes.activityHistory));
      expect(routes, contains(AppRoutes.settings));
    });

    test('Activity History follows settings.view, which is what its endpoint checks', () {
      // /api/audit-logs is gated on settings.view. The sidebar must not offer
      // a screen that then 403s, so the server derives `audit.view` from it
      // rather than granting it to everyone — this asserts the client half.
      expect(routesFor({'audit.view'}), contains(AppRoutes.activityHistory));
      expect(routesFor({'orders.view'}), isNot(contains(AppRoutes.activityHistory)));
    });
  });
}

/// The module list, mirrored rather than imported, so this test keeps working
/// if the catalogue is reorganised — it is about the sidebar, not the
/// catalogue's shape.
class PermissionCatalogModules {
  static const all = [
    'products', 'categories', 'inventory', 'sales', 'orders', 'customers',
    'suppliers', 'purchases', 'returns', 'production', 'reports', 'users',
    'settings', 'financial',
  ];
}
