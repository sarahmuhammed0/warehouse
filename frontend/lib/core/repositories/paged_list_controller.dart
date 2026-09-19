import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/paginated_result.dart';
import 'paged_query.dart';

/// The state every paginated list screen renders from — one shape for
/// Products, Categories, Inventory, Customers, Suppliers, Orders, Sales,
/// Purchases, Returns, Production, Employees, and every other list module,
/// so `AppDataTable`'s loading/error/empty wiring is identical everywhere
/// (§41: one reusable table system, not a bespoke state shape per screen).
class PagedListState<T> {
  const PagedListState({
    required this.query,
    this.items = const [],
    this.total = 0,
    this.loading = true,
    this.error,
  });

  final PagedQuery query;
  final List<T> items;
  final int total;
  final bool loading;
  final String? error;

  int get totalPages => total == 0 ? 1 : (total / query.pageSize).ceil();

  PagedListState<T> copyWith({
    PagedQuery? query,
    List<T>? items,
    int? total,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return PagedListState<T>(
      query: query ?? this.query,
      items: items ?? this.items,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Shared pagination/search/filter/sort/reload logic for every module's
/// list screen. A concrete module subclasses this and implements [fetch] —
/// everything else (page changes, search debouncing via explicit calls,
/// filter changes, error handling, reload-after-mutation) is written once,
/// here, instead of once per module (the brief's explicit "do not build
/// duplicate business logic" rule, applied to state management itself).
///
/// Swapping a module from its local/demo [fetch] implementation to a real
/// API call later means changing exactly one method — every screen built on
/// this controller is unaffected.
abstract class PagedListController<T> extends Notifier<PagedListState<T>> {
  @override
  PagedListState<T> build() {
    final initial = PagedListState<T>(query: const PagedQuery());
    // Fire-and-forget initial load, same pattern as AuthController's
    // restore-session — the first frame renders the loading state, not a
    // blocked build().
    Future.microtask(() => load());
    return initial;
  }

  /// Implemented per module — reads `query` and returns exactly that page.
  Future<PaginatedResult<T>> fetch(PagedQuery query);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await fetch(state.query);
      state = state.copyWith(items: result.items, total: result.total, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Unable to load this list. Please try again.');
    }
  }

  Future<void> reload() => load();

  Future<void> changePage(int page) async {
    state = state.copyWith(query: state.query.copyWith(page: page));
    await load();
  }

  Future<void> changePageSize(int pageSize) async {
    state = state.copyWith(query: state.query.copyWith(page: 1, pageSize: pageSize));
    await load();
  }

  Future<void> search(String text) async {
    state = state.copyWith(query: state.query.copyWith(page: 1, search: text));
    await load();
  }

  Future<void> setFilters(Map<String, Object?> filters) async {
    state = state.copyWith(query: state.query.copyWith(page: 1, filters: filters));
    await load();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(query: state.query.copyWith(page: 1, filters: const {}));
    await load();
  }

  Future<void> sort(String field, bool ascending) async {
    state = state.copyWith(query: state.query.copyWith(sortField: field, sortAscending: ascending));
    await load();
  }
}
