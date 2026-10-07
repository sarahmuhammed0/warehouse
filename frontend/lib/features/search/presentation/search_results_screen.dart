import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/paged_query.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/search/global_search_bar.dart';
import '../../../theme/app_colors.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_typography.dart';
import '../../customers/data/customer_models.dart';
import '../../customers/data/customer_providers.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_providers.dart';
import '../../products/data/product_models.dart';
import '../../products/data/product_providers.dart';
import '../../suppliers/data/supplier_models.dart';
import '../../suppliers/data/supplier_providers.dart';

class _SearchResults {
  const _SearchResults({
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.orders,
    this.modulesRefused = 0,
    this.modulesSearched = 0,
  });
  final List<Product> products;
  final List<Customer> customers;
  final List<Supplier> suppliers;
  final List<Order> orders;

  /// How many modules refused the lookup, and how many were asked.
  ///
  /// A role that cannot open Products is not a failed search — it is a search
  /// over the modules that role CAN see. But if every one of them refused, the
  /// search genuinely failed and saying "no results" would be a lie.
  final int modulesRefused;
  final int modulesSearched;

  bool get allRefused => modulesSearched > 0 && modulesRefused == modulesSearched;
  bool get someRefused => modulesRefused > 0 && !allRefused;
  int get total => products.length + customers.length + suppliers.length + orders.length;
}

/// Global search (spec §17/§30/§32) — real, module-aware search across
/// Products (name/SKU/barcode/code), Orders (order #/customer/phone via
/// customer name match), Customers & Suppliers (name/phone), exactly the
/// per-entity match rules the spec lists, grouped by module in one results
/// view rather than a per-module search UI.
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.query});
  final String query;

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  // Created once per query, not inline in `build()` — a `FutureBuilder`
  // given a freshly-constructed `Future` on every build never settles
  // (each rebuild restarts it as "loading" again, and completing that new
  // future triggers a `setState`-driven rebuild that restarts it again,
  // repeating forever). `initState`/`didUpdateWidget` are the correct place
  // to (re)kick off a fetch tied to a `ConsumerStatefulWidget`'s lifecycle.
  late Future<_SearchResults> _future = _runSearch(widget.query);

  /// The query, editable here.
  ///
  /// Without this the screen was a dead end: the compact header has a search
  /// BUTTON rather than a field, and it navigated here with no query at all —
  /// which showed every product in the business under the heading `Search: ""`,
  /// with nowhere to type what was actually wanted.
  late final TextEditingController _input = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant SearchResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _input.text = widget.query;
      _future = _runSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Through the router, so the query lives in the URL: a result can be shared,
  /// the back button returns to the previous search, and a reload keeps it.
  void _submit(String raw) {
    final query = raw.trim();
    if (query == widget.query) return;
    context.go('${AppRoutes.search}?q=${Uri.encodeQueryComponent(query)}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PageScaffold(
      title: '${l10n.search}: "${widget.query}"',
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          // The query, on the results page itself. Arriving here from the
          // header's search BUTTON used to leave no way to say what was wanted.
          GlobalSearchBar(key: const ValueKey('searchInput'), controller: _input, autofocus: true, onSubmitted: _submit),
          FutureBuilder<_SearchResults>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
              }
              // Never an endless spinner: a thrown search says so and offers
              // another go.
              if (snapshot.hasError || !snapshot.hasData) {
                return AppErrorState(message: l10n.unableToLoad, onRetry: () => setState(() => _future = _runSearch(widget.query)));
              }

              final results = snapshot.data!;
              if (widget.query.trim().isEmpty) {
                return AppEmptyState(icon: Icons.search, title: l10n.search, description: l10n.searchPrompt);
              }
              if (results.allRefused) {
                return AppErrorState(message: l10n.unableToLoad, onRetry: () => setState(() => _future = _runSearch(widget.query)));
              }

              final products = results.products;
              final customers = results.customers;
              final suppliers = results.suppliers;
              final orders = results.orders;
              final totalResults = results.total;

              if (totalResults == 0) {
                return AppEmptyState(icon: Icons.search_off, title: l10n.emptyStateDefaultTitle, description: l10n.emptyStateDefaultDescription);
              }

          // A plain Column, not ListView — PageScaffold already wraps
          // `body` in a SingleChildScrollView, so a nested ListView (its
          // own unbounded-height viewport) crashes with "Vertical viewport
          // was given unbounded height."
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (products.isNotEmpty)
                AppCard(
                  title: Text(l10n.navProducts),
                  child: Column(children: [for (final p in products) ListTile(contentPadding: EdgeInsets.zero, title: Text(p.name), subtitle: Text(p.sku ?? p.code), onTap: () => context.push(AppRoutes.productDetail(p.id)))]),
                ),
              if (customers.isNotEmpty)
                AppCard(
                  title: Text(l10n.navCustomers),
                  child: Column(children: [for (final c in customers) ListTile(contentPadding: EdgeInsets.zero, title: Text(c.fullName), subtitle: Text(c.phone), onTap: () => context.push(AppRoutes.customerDetail(c.id)))]),
                ),
              if (suppliers.isNotEmpty)
                AppCard(
                  title: Text(l10n.navSuppliers),
                  child: Column(children: [for (final s in suppliers) ListTile(contentPadding: EdgeInsets.zero, title: Text(s.name), subtitle: Text(s.phone), onTap: () => context.push(AppRoutes.supplierDetail(s.id)))]),
                ),
              if (orders.isNotEmpty)
                AppCard(
                  title: Text(l10n.navOrders),
                  child: Column(children: [for (final o in orders) ListTile(contentPadding: EdgeInsets.zero, title: Text(o.orderNumber), subtitle: Text(o.customerName ?? '—'), onTap: () => context.push(AppRoutes.orderDetail(o.id)))]),
                ),
              const SizedBox(height: 8),
              Text('$totalResults results', style: AppTypography.caption),
              // Said once, quietly: some of these modules were not searched
              // because this role cannot open them. Better than silently
              // returning fewer results than the person expects.
              if (results.someRefused)
                Text(l10n.searchPartial, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
            ],
          );
            },
          ),
        ],
      ),
    );
  }

  /// Searches every module the signed-in role can actually open.
  ///
  /// Two things were wrong here. The four lookups ran one after another, and a
  /// single refusal took the whole screen down with it: a role without
  /// `products.view` — an Accountant, by design — threw out of the first await,
  /// the future never completed, and the builder's `!snapshot.hasData` left a
  /// spinner turning forever. Searching as anyone but an owner simply hung.
  ///
  /// So they run together, and a module that refuses is counted rather than
  /// thrown: the Accountant gets customer and order results instead of nothing.
  /// If EVERY module refuses, that is a real failure and is reported as one —
  /// "no results" would be a lie.
  Future<_SearchResults> _runSearch(String raw) async {
    final query = raw.trim();
    // An empty query is not a search. `buildListQuery` omits the parameter when
    // it is blank, so asking anyway returned every unfiltered row in the
    // business and presented them as matches — which is what "search doesn't
    // work" looked like.
    if (query.isEmpty) {
      return const _SearchResults(products: [], customers: [], suppliers: [], orders: []);
    }

    final paged = PagedQuery(search: query, pageSize: 5);
    var refused = 0;
    Future<List<T>> lookUp<T>(Future<PaginatedResult<T>> Function() fetch) async {
      try {
        return (await fetch()).items;
      } catch (_) {
        refused += 1;
        return const [];
      }
    }

    final results = await Future.wait([
      lookUp(() => ref.read(productRepositoryProvider).list(paged)),
      lookUp(() => ref.read(customerRepositoryProvider).list(paged)),
      lookUp(() => ref.read(supplierRepositoryProvider).list(paged)),
      lookUp(() => ref.read(orderRepositoryProvider).list(paged)),
    ]);

    return _SearchResults(
      products: results[0].cast<Product>(),
      customers: results[1].cast<Customer>(),
      suppliers: results[2].cast<Supplier>(),
      orders: results[3].cast<Order>(),
      modulesRefused: refused,
      modulesSearched: 4,
    );
  }
}
