/// The demo tenants every `Local*Repository` tags its seeded records with.
///
/// This exists so the System Admin's cross-tenant aggregates (spec §56's
/// "total products / total orders / total sales across system") are
/// *derived from real records* rather than hard-coded per-business numbers
/// that correspond to nothing. Before this, `AdminBusiness` carried fields
/// like `productCount: 412` while the entire demo dataset held 13 products
/// — so the admin dashboard's totals, the per-business summary, and the
/// actual records a drill-down could show were three unrelated sets of
/// numbers. Now there is one source of truth: the records themselves (see
/// `features/admin/data/admin_aggregate_providers.dart`).
///
/// Lives in `core/repositories/` rather than under `features/admin/` on
/// purpose: Products/Orders/Employees tag their rows with these ids, and a
/// business module must never import the System Admin feature.
class DemoBusiness {
  const DemoBusiness({required this.id, required this.name, required this.type});

  final String id;
  final String name;

  /// Matches the spec §50 factory-type labels the admin business list shows.
  final String type;
}

/// Stable ids — referenced directly by each repository's seed data.
const String kDemoBusinessKarwan = 'biz-1';
const String kDemoBusinessErbil = 'biz-2';
const String kDemoBusinessCityStore = 'biz-3';
const String kDemoBusinessNorthern = 'biz-4';

/// `type` is the WIRE value the backend's `business_type` enum uses, not the
/// human label — the same thing a real record holds, so demo and backend data
/// have one shape and the screens need one way to display it. These carried
/// labels until the admin edit screen's type dropdown was found to crash in
/// backend mode: its options were keyed by label, so the server's
/// `furniture_factory` matched none of them. See `businessTypeLabelFor`.
const List<DemoBusiness> kDemoBusinesses = [
  DemoBusiness(id: kDemoBusinessKarwan, name: 'Karwan Furniture Factory', type: 'furniture_factory'),
  DemoBusiness(id: kDemoBusinessErbil, name: 'Erbil Central Warehouse', type: 'warehouse'),
  DemoBusiness(id: kDemoBusinessCityStore, name: 'City Storage Store', type: 'storage_store'),
  DemoBusiness(id: kDemoBusinessNorthern, name: 'Northern Distribution Center', type: 'distribution_center'),
];

/// Which tenant a record created at runtime (e.g. a business user adding a
/// product in demo mode) belongs to. The business-side app is single-tenant
/// in demo mode — it shows the whole demo dataset rather than filtering to
/// one business (see docs/frontend-demo-mode.md) — so new rows need a
/// tenant only so the System Admin's per-business views stay coherent.
const String kDemoBusinessForNewRecords = kDemoBusinessKarwan;
