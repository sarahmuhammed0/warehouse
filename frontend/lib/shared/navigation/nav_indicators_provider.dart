import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/data/registration_queue_repository.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../routing/app_routes.dart';
import 'nav_indicator.dart';

/// What each navigation item is currently asking for, keyed by route.
///
/// A route absent from the map shows nothing. Entries are built from live data
/// — never a flag someone sets and forgets — so an item carries its badge for
/// exactly as long as the work behind it is outstanding and drops it the moment
/// that work is done.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT THE SYSTEM ADMIN AREA ACTUALLY HAS
///
/// Every admin screen was audited before this was written, and only ONE of them
/// has a state that asks anything of the administrator. The rest are listed
/// here with the reason, because "why does Orders not have a badge" is a fair
/// question and the answer should not have to be rediscovered.
///
///   Registrations  YES — businesses sitting at status `pending`, with Approve
///                  and Reject on screen. A decision nobody else can make.
///
///   Businesses     No state of its own. A business at `pending` IS a pending
///                  registration, so badging both would count one queue twice
///                  and send the administrator to the screen that cannot act on
///                  it. `disabled` is not pending either — somebody disabled it
///                  on purpose, and it stays that way until somebody decides
///                  otherwise.
///
///   Employees      Read-only cross-tenant drill-downs. §57 gives the platform
///   Products       operator oversight, not operation: there is no admin action
///   Orders         on another business's staff, stock or orders, so there is
///   Sales          nothing that could ever be "pending" for the admin. An
///                  order at status `pending` is pending for ITS BUSINESS, and
///                  badging it here would send the administrator to a screen
///                  with no button on it.
///
///   Dashboard      A summary of the others. A badge here would duplicate
///                  whatever is already badged below it.
///
///   Notifications  §31's feed is `requireAccountType("business_user")` — a
///   (the bell)     System Admin belongs to no business and has no
///                  notifications to be unread. The bell already badges its
///                  own unread count for business users and is left alone.
///
/// Adding anything else would mean inventing a state the application does not
/// have. If one is added later — a failed backup is the obvious candidate, and
/// would be a `warning` rather than a `pendingAction` — it belongs here.
final navIndicatorsProvider = Provider<Map<String, NavIndicator>>((ref) {
  final indicators = <String, NavIndicator>{};

  // Nothing is fetched unless a System Admin is signed in.
  //
  // Without this guard, every screen that draws navigation — which is all of
  // them — asked for the pending-registration queue, including for business
  // users, whose session cannot reach that endpoint at all. The badge would
  // never appear for them (the 403 resolves to no indicator), so it would have
  // looked correct while firing a failing admin request on every page they
  // opened.
  //
  // A System Admin belongs to no business, which is what `business == null`
  // means here — the same signal `currentRoleProvider` uses to decide there is
  // no business-scoped role to resolve.
  final auth = ref.watch(authControllerProvider);
  final isSystemAdmin = auth is AuthAuthenticated && auth.business == null;
  if (!isSystemAdmin) return indicators;

  // Pending business registrations (§2/§57).
  //
  // Read from the same provider the Registrations screen itself renders, which
  // is what makes the badge self-clearing: approving or rejecting invalidates
  // it, both the list and this count rebuild, and the badge disappears when the
  // last one is decided. Nothing has to remember to clear it.
  //
  // While loading or on error the entry is simply absent — a count that is not
  // known yet must not be drawn as a number, and a failed fetch must not
  // announce work that may not exist.
  final pending = ref.watch(pendingRegistrationsProvider).asData?.value;
  if (pending != null && pending.isNotEmpty) {
    indicators[AppRoutes.adminRegistrations] = NavIndicator.pendingAction(pending.length);
  }

  return indicators;
});

/// The indicator for one route, or null. Watching this rather than the whole
/// map means an item only rebuilds when ITS own badge changes.
final navIndicatorProvider = Provider.family<NavIndicator?, String>((ref, route) {
  return ref.watch(navIndicatorsProvider.select((all) => all[route]));
});
