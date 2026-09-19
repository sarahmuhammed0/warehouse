import '../network/paginated_result.dart';
import 'paged_query.dart';

/// Marks a repository implementation as backed by clearly-isolated,
/// in-memory demo data — never a real API — per the frontend-first phase's
/// explicit rule (§3/§48): temporary local data must never be allowed to
/// look like production backend integration. Every `Local*Repository` class
/// implements this so it's mechanically obvious, from the type alone, which
/// repositories are demo-backed and still need a real API implementation —
/// see `docs/frontend-backend-contract-notes.md` for the full list.
mixin DemoRepository {
  /// True for every implementation in this codebase today. A real
  /// `Api*Repository` (added once the backend module exists) would not
  /// mix this in at all.
  bool get isDemoData => true;
}

/// Applies a [PagedQuery]'s paging (and, if [matches]/[compare] are given,
/// its search and sort) to an in-memory list — the one place that logic is
/// written, so every `Local*Repository`'s `list()` method is a two-line call
/// into this instead of hand-rolled slicing per module.
PaginatedResult<T> paginateInMemory<T>(
  List<T> all,
  PagedQuery query, {
  bool Function(T item, String search)? matches,
  Comparable Function(T item)? sortKey,
}) {
  var filtered = all;
  if (query.search.trim().isNotEmpty && matches != null) {
    final q = query.search.trim().toLowerCase();
    filtered = filtered.where((item) => matches(item, q)).toList();
  }
  if (query.sortField != null && sortKey != null) {
    filtered = [...filtered]..sort((a, b) {
      final cmp = sortKey(a).compareTo(sortKey(b));
      return query.sortAscending ? cmp : -cmp;
    });
  }

  final start = (query.page - 1) * query.pageSize;
  final end = (start + query.pageSize).clamp(0, filtered.length);
  final pageItems = start >= filtered.length ? <T>[] : filtered.sublist(start, end);

  return PaginatedResult<T>(
    items: pageItems,
    page: query.page,
    pageSize: query.pageSize,
    total: filtered.length,
  );
}

/// A short, simulated-latency delay so demo-backed screens still exercise
/// their real loading states (skeletons, disabled buttons while saving)
/// instead of resolving instantly — the same reason a real API call would
/// show one, just without a network involved.
///
/// Deliberately a chain of microtasks, not `Future.delayed` (a real
/// `Timer`): with dozens of screens now chaining several demo repositories
/// per page (e.g. Inventory awaiting Products awaiting its own delay),
/// `Timer`-based delays becomes a genuine `flutter_test` hazard —
/// `pumpAndSettle` can decide the widget tree has quiesced while a `Timer`
/// still hasn't fired, then fail teardown's "no pending timers" invariant.
/// A microtask-based delay still yields a real frame boundary (so loading
/// states are genuinely observable) but is always fully drained by
/// `pumpAndSettle`/`flushMicrotasks`, never left pending.
Future<void> simulatedLatency() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.value();
  }
}
