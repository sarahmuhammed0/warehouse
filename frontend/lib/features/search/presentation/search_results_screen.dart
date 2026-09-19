import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/paged_query.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_empty_state.dart';
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
  const _SearchResults({required this.products, required this.customers, required this.suppliers, required this.orders});
  final List<Product> products;
  final List<Customer> customers;
  final List<Supplier> suppliers;
  final List<Order> orders;
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
  late Future<_SearchResults> _future = _runSearch(PagedQuery(search: widget.query, pageSize: 5));

  @override
  void didUpdateWidget(covariant SearchResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _future = _runSearch(PagedQuery(search: widget.query, pageSize: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PageScaffold(
      title: '${l10n.search}: "${widget.query}"',
      body: FutureBuilder<_SearchResults>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final products = snapshot.data!.products;
          final customers = snapshot.data!.customers;
          final suppliers = snapshot.data!.suppliers;
          final orders = snapshot.data!.orders;
          final totalResults = products.length + customers.length + suppliers.length + orders.length;

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
            ],
          );
        },
      ),
    );
  }

  Future<_SearchResults> _runSearch(PagedQuery query) async {
    final products = await ref.read(productRepositoryProvider).list(query);
    final customers = await ref.read(customerRepositoryProvider).list(query);
    final suppliers = await ref.read(supplierRepositoryProvider).list(query);
    final orders = await ref.read(orderRepositoryProvider).list(query);
    return _SearchResults(products: products.items, customers: customers.items, suppliers: suppliers.items, orders: orders.items);
  }
}
