/// Route path + name constants (architecture §23). Every `go()`/`GoRoute`
/// reference uses these, never a magic string — this is also what
/// `shared/navigation/nav_items.dart` points at when building the sidebar,
/// so a path only ever exists in one place.
class AppRoutes {
  AppRoutes._();

  // Business application (persistent shell)
  static const dashboard = '/dashboard';
  static const products = '/products';
  static const productNew = '/products/new';
  static String productDetail(String id) => '/products/$id';
  static String productEdit(String id) => '/products/$id/edit';

  static const categories = '/categories';

  static const inventory = '/inventory';
  static const inventoryTransfers = '/inventory/transfers';
  static const inventoryLocations = '/inventory/locations';

  static const sales = '/sales';
  static const saleNew = '/sales/new';

  static const orders = '/orders';
  static const orderNew = '/orders/new';
  static String orderDetail(String id) => '/orders/$id';

  static const customers = '/customers';
  static String customerDetail(String id) => '/customers/$id';

  static const suppliers = '/suppliers';
  static String supplierDetail(String id) => '/suppliers/$id';

  static const purchases = '/purchases';
  static const purchaseNew = '/purchases/new';
  static String purchaseDetail(String id) => '/purchases/$id';

  static const returns = '/returns';
  static const returnNew = '/returns/new';
  static String returnDetail(String id) => '/returns/$id';

  static const production = '/production';
  static const productionNew = '/production/new';
  static String productionDetail(String id) => '/production/$id';

  static const employees = '/employees';
  static const employeeNew = '/employees/new';
  static String employeeEdit(String id) => '/employees/$id/edit';
  static const roles = '/employees/roles';

  static const reports = '/reports';
  static const operationalReports = '/reports/operational';
  static const businessReports = '/reports/business';

  static const documents = '/documents';
  static const pdfTemplateBuilder = '/documents/pdf-template';
  static const documentNumbering = '/documents/numbering';

  static const activityHistory = '/activity-history';
  static const notifications = '/notifications';
  static const search = '/search';

  static const settings = '/settings';
  static const settingsBusiness = '/settings/business';
  static const settingsUsers = '/settings/users';
  static const settingsInventory = '/settings/inventory';
  static const settingsSales = '/settings/sales';
  static const settingsPdf = '/settings/pdf';
  static const settingsProduction = '/settings/production';
  static const settingsSecurity = '/settings/security';
  static const settingsCustomFields = '/settings/custom-fields';
  static const settingsBackup = '/settings/backup';

  // System Admin (separate shell — architecture §56/§57)
  static const adminDashboard = '/admin';
  static const adminBusinesses = '/admin/businesses';
  static String adminBusinessDetail(String id) => '/admin/businesses/$id';

  // Spec §57's business controls. Edit and Reports are screens of their own
  // so the back arrow returns to the business they were opened from;
  // Disable/Activate and Reset password are dialogs over the detail screen
  // (they act on it rather than navigating away from it), and Manage users
  // reuses the drill-down's own per-business Employees route.
  static String adminBusinessEdit(String id) => '/admin/businesses/$id/edit';
  static String adminBusinessReports(String id) => '/admin/businesses/$id/reports';

  // System Admin drill-down: dashboard stat → per-business overview →
  // that business's records → one record. Every level is a real route, so
  // each step is an ordinary router push and the back arrow pops one level
  // (never a hard-coded "home"). A System Admin never lands on the
  // business shell's own operational tables — these are admin-shell
  // screens scoped to an explicitly chosen `businessId`.
  static const adminEmployees = '/admin/employees';
  static String adminEmployeesFor(String businessId) => '/admin/employees/$businessId';
  static String adminEmployeeDetail(String businessId, String id) => '/admin/employees/$businessId/$id';

  static const adminProducts = '/admin/products';
  static String adminProductsFor(String businessId) => '/admin/products/$businessId';
  static String adminProductDetail(String businessId, String id) => '/admin/products/$businessId/$id';

  static const adminOrders = '/admin/orders';
  static String adminOrdersFor(String businessId) => '/admin/orders/$businessId';
  static String adminOrderDetail(String businessId, String id) => '/admin/orders/$businessId/$id';

  static const adminSales = '/admin/sales';
  static String adminSalesFor(String businessId) => '/admin/sales/$businessId';
  static String adminSaleDetail(String businessId, String id) => '/admin/sales/$businessId/$id';

  // Retained from Phase 0 — a dev utility, not part of the business nav.
  static const systemStatus = '/system-status';

  // Reserved for Phase 2 — not implemented yet (§27: no auth logic this
  // phase), but the path exists now so the redirect guard added in Phase 2
  // has somewhere to send an unauthenticated user without touching this
  // file again.
  static const login = '/login';
}
