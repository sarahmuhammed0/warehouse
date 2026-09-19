/// The one query shape every module's `list()` repository method takes
/// (Products, Categories, Inventory, Customers, Suppliers, Orders, ...) —
/// matches the server-side pagination/filtering/sorting contract the
/// backend is expected to expose later (architecture §26/§29), so a
/// repository's local (demo) implementation and its future real API
/// implementation share the exact same request shape and nothing about the
/// calling screen changes when one replaces the other.
class PagedQuery {
  const PagedQuery({
    this.page = 1,
    this.pageSize = 20,
    this.search = '',
    this.filters = const <String, Object?>{},
    this.sortField,
    this.sortAscending = true,
  });

  final int page;
  final int pageSize;
  final String search;

  /// Module-specific filter values (e.g. `{'status': 'active', 'categoryId': 4}`)
  /// — deliberately untyped here so this one class serves every module;
  /// each repository's local implementation reads only the keys it defines.
  final Map<String, Object?> filters;

  final String? sortField;
  final bool sortAscending;

  PagedQuery copyWith({
    int? page,
    int? pageSize,
    String? search,
    Map<String, Object?>? filters,
    String? sortField,
    bool? sortAscending,
    bool clearSort = false,
  }) {
    return PagedQuery(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      filters: filters ?? this.filters,
      sortField: clearSort ? null : (sortField ?? this.sortField),
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
