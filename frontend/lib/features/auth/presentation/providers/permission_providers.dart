import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../employees/data/employee_models.dart';
import '../../../employees/data/employee_providers.dart';
import '../../../employees/data/employee_repository.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// Resolves the signed-in BUSINESS user's role/permissions (spec §23/§24)
/// from their linked `Employee` record — the seam `employee_models.dart`'s
/// top doc comment and `NavItem.permissionKey`'s doc comment have pointed
/// to since Phase 1.
///
/// Explicitly NOT a security boundary (spec §35: "Never trust frontend
/// permissions... enforced on the Node.js backend") — exactly like the
/// router's redirect guards, this only controls what the UI *shows*.
///
/// **Deliberately synchronous** (`Provider`, not `FutureProvider`) — this
/// is watched from `routing/app_router.dart`'s `_enabledBusinessNavItems`,
/// which runs while building the `GoRouter` itself; an async provider's
/// first Loading→Data transition there makes `routerProvider` rebuild a
/// **brand new `GoRouter`**, discarding whatever route was just pushed.
/// See `LocalEmployeeRepository.roleForPhoneSync`'s doc comment for how
/// this was found (a genuine bug, not a hypothetical one) and why a
/// synchronous fast path is safe here: all demo data is already fully
/// seeded synchronously before any repository method is ever called.
///
/// **Demo mode only, for now.** Each demo-mode business login (see
/// `demo_auth_repository.dart`'s per-role phone constants) uses a phone
/// number that matches a seeded `Employee`, so its role/permissions
/// resolve for real — this is what lets the frontend demonstrate that the
/// UI actually changes per role (docs/roles-and-permissions.md). A real
/// backend-mode session has no such linked `Employee` yet — the backend
/// doesn't return role/permission data in Phase 2's auth response, and
/// adding that is backend work this pass explicitly doesn't do — so it
/// resolves to `null` permissions, which [hasPermission] treats as
/// "unrestricted": this adds a real capability in demo mode without
/// silently taking one away from backend-mode sessions that predate it.
final currentRoleProvider = Provider<Role?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated || auth.business == null) return null;
  final repo = ref.watch(employeeRepositoryProvider);
  if (repo is! LocalEmployeeRepository) return null;
  return repo.roleForPhoneSync(auth.account.phone);
});

/// `null` = unrestricted (no linked `Employee` — a real backend-mode
/// session, or a demo identity that somehow doesn't match one). A non-null
/// set is the actual, resolvable grant list from that role's permissions —
/// see [hasPermission].
final currentPermissionsProvider = Provider<Set<String>?>((ref) {
  return ref.watch(currentRoleProvider)?.permissions;
});

/// The one place every gated nav item/button/field checks against —
/// `null` permissions (see [currentPermissionsProvider]) always passes,
/// by design: it means "no role resolved to restrict against", never
/// "explicitly denied". A resolved (non-null) set is checked literally.
bool hasPermission(Set<String>? permissions, String module, String action) {
  if (permissions == null) return true;
  return permissions.contains(PermissionCatalog.key(module, action));
}
