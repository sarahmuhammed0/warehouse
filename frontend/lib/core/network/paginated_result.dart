/// Generic wrapper for any paginated list endpoint (architecture §26/§29 —
/// every list endpoint returns `data` + a `meta` block with page/pageSize/
/// total). Feature repositories parse their own item type `T` and hand back
/// one of these instead of a bare `List<T>`, so screens always have the
/// pagination info available without re-deriving it per feature.
class PaginatedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  const PaginatedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  bool get hasMore => page * pageSize < total;
}
