import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Factory type configuration (spec §33/§3) — the seven business types
/// System Admin can assign when creating a business, each defaulting a
/// different module set. This is the frontend half of the requirement:
/// "the frontend must show module configuration based on business type...
/// do not permanently hard-code module behavior into UI widgets" — the
/// mapping below is data, read by `routing/app_router.dart`'s sidebar
/// filter, not an `if (businessType == ...)` scattered across screens.
enum BusinessType { furnitureFactory, generalFactory, warehouse, storageStore, wholesaleStore, distributionCenter, custom }

/// Matches each `NavItem.moduleKey` (`shared/navigation/nav_items.dart`).
/// `custom` enables everything — a business that picked "Custom" during
/// System Admin onboarding is expected to enable/disable modules itself
/// later (Settings → a future "Modules" section), not have this table
/// guess for it.
const Map<BusinessType, Set<String>> businessTypeModules = {
  BusinessType.furnitureFactory: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'production', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.generalFactory: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'production', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.warehouse: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.storageStore: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.wholesaleStore: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.distributionCenter: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
  BusinessType.custom: {'dashboard', 'products', 'categories', 'inventory', 'sales', 'orders', 'customers', 'suppliers', 'purchases', 'returns', 'production', 'employees', 'reports', 'documents', 'activityHistory', 'settings'},
};

/// The exact labels spec §50 lists for the seven types the System Admin can
/// assign. Kept here beside [businessTypeModules] so the label a business
/// record stores and the key that decides its modules can't drift apart —
/// `LocalAdminRepository`'s demo tenants and the System Admin's Edit form
/// both spell a type through this function, never as a loose string.
String businessTypeLabel(BusinessType type) => switch (type) {
      BusinessType.furnitureFactory => 'Furniture Factory',
      BusinessType.generalFactory => 'General Factory',
      BusinessType.warehouse => 'Warehouse',
      BusinessType.storageStore => 'Storage Store',
      BusinessType.wholesaleStore => 'Wholesale Store',
      BusinessType.distributionCenter => 'Distribution Center',
      BusinessType.custom => 'Custom',
    };

/// The value the backend's `business_type` ENUM accepts. Separate from
/// [businessTypeLabel] on purpose: the label is human text that may be
/// translated or reworded, while this is a wire format the database
/// validates against — sending "Furniture Factory" where the column expects
/// `furniture_factory` is rejected outright. Kept in this file so the two
/// cannot drift.
String businessTypeApiValue(BusinessType type) => switch (type) {
      BusinessType.furnitureFactory => 'furniture_factory',
      BusinessType.generalFactory => 'general_factory',
      BusinessType.warehouse => 'warehouse',
      BusinessType.storageStore => 'storage_store',
      BusinessType.wholesaleStore => 'wholesale_store',
      BusinessType.distributionCenter => 'distribution_center',
      BusinessType.custom => 'custom',
    };

/// The reverse of [businessTypeApiValue]: the wire value a record stores, back
/// to the [BusinessType] it means. Null for anything unrecognised, which is the
/// honest answer — a type this build has never heard of must not be silently
/// rendered as one it has.
BusinessType? businessTypeFromApiValue(String? value) {
  if (value == null) return null;
  for (final type in BusinessType.values) {
    if (businessTypeApiValue(type) == value) return type;
  }
  return null;
}

/// Human text for a business type as it is STORED on a record.
///
/// Needed because the two sides spell it differently and both reach the screen:
/// the server stores `furniture_factory`, while demo data and the registration
/// flow have historically carried the label itself. Four admin screens printed
/// the stored string straight out, so in backend mode they displayed
/// `furniture_factory` to the operator.
///
/// An unrecognised value is returned unchanged rather than blanked or replaced:
/// if a record somehow holds something this build does not know, showing it is
/// more useful than hiding it.
String businessTypeLabelFor(String? stored) {
  if (stored == null || stored.trim().isEmpty) return '—';
  final known = businessTypeFromApiValue(stored);
  return known == null ? stored : businessTypeLabel(known);
}

/// Which type the *demo* business is — a real deployment reads this from
/// the authenticated business's own record (set once at System Admin
/// creation time, §3); there is no such record in this frontend-only
/// phase, so it's a Settings-adjustable stand-in, defaulting to Furniture
/// Factory (this app's own running example throughout the demo data).
final businessTypeProvider = NotifierProvider<BusinessTypeController, BusinessType>(BusinessTypeController.new);

class BusinessTypeController extends Notifier<BusinessType> {
  @override
  BusinessType build() => BusinessType.furnitureFactory;

  void set(BusinessType type) => state = type;
}
