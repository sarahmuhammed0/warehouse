/// Route path + name constants (architecture §23). Every `go()`/`GoRoute`
/// reference uses these, never a magic string — this is also what
/// `shared/navigation/nav_items.dart` points at when building the sidebar,
/// so a path only ever exists in one place.
class AppRoutes {
  AppRoutes._();

  // Business application (persistent shell)
  static const dashboard = '/dashboard';
  static const products = '/products';
  static const categories = '/categories';
  static const inventory = '/inventory';
  static const sales = '/sales';
  static const orders = '/orders';
  static const customers = '/customers';
  static const suppliers = '/suppliers';
  static const purchases = '/purchases';
  static const returns = '/returns';
  static const production = '/production';
  static const employees = '/employees';
  static const reports = '/reports';
  static const documents = '/documents';
  static const activityHistory = '/activity-history';
  static const settings = '/settings';

  // System Admin (separate shell — architecture §56/§57)
  static const adminDashboard = '/admin';
  static const adminBusinesses = '/admin/businesses';

  // Retained from Phase 0 — a dev utility, not part of the business nav.
  static const systemStatus = '/system-status';

  // Reserved for Phase 2 — not implemented yet (§27: no auth logic this
  // phase), but the path exists now so the redirect guard added in Phase 2
  // has somewhere to send an unauthenticated user without touching this
  // file again.
  static const login = '/login';
}
