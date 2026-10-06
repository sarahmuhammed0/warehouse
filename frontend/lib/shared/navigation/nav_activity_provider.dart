import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../routing/app_routes.dart';
import 'nav_activity_repository.dart';
import 'nav_seen_store.dart';

/// Navigation route → the entity key the server counts for it.
///
/// Only items that are a LIST OF RECORDS are here. A summary (the dashboards)
/// would double-count whatever is badged below it; a hub (Reports, Settings,
/// Documents) has no arrivals of its own; and the activity log is excluded on
/// purpose — every action in the system writes to it, so it would carry a badge
/// permanently and teach people to ignore all of them.
const Map<String, String> businessActivityEntities = {
  AppRoutes.products: 'products',
  AppRoutes.categories: 'categories',
  AppRoutes.inventory: 'inventory',
  AppRoutes.sales: 'sales',
  AppRoutes.orders: 'orders',
  AppRoutes.customers: 'customers',
  AppRoutes.suppliers: 'suppliers',
  AppRoutes.purchases: 'purchases',
  AppRoutes.returns: 'returns',
  AppRoutes.production: 'production',
  AppRoutes.employees: 'employees',
};

/// The System Admin's nav, counted across every tenant (§57).
///
/// `adminRegistrations` is deliberately absent: that badge is a queue of
/// decisions, not a record of arrivals. It must not clear because somebody
/// looked at the screen — only because the last application was decided. It
/// stays in `navIndicatorsProvider`, read from the same provider the
/// Registrations screen itself renders.
const Map<String, String> adminActivityEntities = {
  AppRoutes.adminBusinesses: 'businesses',
  AppRoutes.adminEmployees: 'employees',
  AppRoutes.adminProducts: 'products',
  AppRoutes.adminOrders: 'orders',
  AppRoutes.adminSales: 'sales',
};

/// Which account is signed in, and which map applies to it.
///
/// A System Admin belongs to no business — the same signal `navIndicatorsProvider`
/// uses — and sees the platform-wide counts rather than a tenant's.
({int accountId, bool isSystemAdmin, Map<String, String> entities})? _audience(Ref ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;
  final isSystemAdmin = auth.business == null;
  return (
    accountId: auth.account.id,
    isSystemAdmin: isSystemAdmin,
    entities: isSystemAdmin ? adminActivityEntities : businessActivityEntities,
  );
}

/// How many records have arrived on each navigation route since it was opened.
///
/// A route with no stored mark is NOT reported as "everything that exists".
/// A fresh install would then badge every item in the navigation at once, which
/// says nothing and trains people to dismiss the badges. The first sight of a
/// route is recorded as seen instead, and the count starts from there — see
/// [markNavRouteSeen].
final navActivityProvider = FutureProvider<Map<String, int>>((ref) async {
  final audience = _audience(ref);
  if (audience == null) return const {};

  final seen = await ref.watch(navSeenStoreProvider).read('${audience.accountId}');

  // Only routes that have been seen at least once can have a "since".
  final since = <String, DateTime>{};
  for (final entry in audience.entities.entries) {
    final mark = seen[entry.key];
    if (mark != null) since[entry.value] = mark;
  }
  if (since.isEmpty) return const {};

  final counts = await ref
      .watch(navActivityRepositoryProvider)
      .counts(since, asSystemAdmin: audience.isSystemAdmin);

  // Back from entity keys to routes. Two admin routes share no entity, and the
  // business map is one-to-one, so this cannot collide.
  return {
    for (final entry in audience.entities.entries)
      if ((counts[entry.value] ?? 0) > 0) entry.key: counts[entry.value]!,
  };
});

/// Records that [route] has been looked at, and refreshes the counts.
///
/// Called when a navigation destination is actually on screen. Marking a route
/// seen clears only ITS badge — each item carries its own timestamp, so opening
/// Products never silences Orders.
Future<void> markNavRouteSeen(Ref ref, String route) async {
  final audience = _audience(ref);
  if (audience == null || !audience.entities.containsKey(route)) return;

  final store = ref.read(navSeenStoreProvider);
  final seen = await store.read('${audience.accountId}');
  seen[route] = DateTime.now().toUtc();
  await store.write('${audience.accountId}', seen);
  ref.invalidate(navActivityProvider);
}

/// The side of [markNavRouteSeen] a widget can call.
final navSeenMarkerProvider = Provider<Future<void> Function(String)>((ref) {
  return (route) => markNavRouteSeen(ref, route);
});
