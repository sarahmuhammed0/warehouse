import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../feedback/app_empty_state.dart';
import '../feedback/app_error_state.dart';
import '../feedback/app_skeleton.dart';
import '../layout/responsive/app_breakpoints.dart';
import 'table_column.dart';

/// The enterprise data table foundation (§11) every list-of-records module
/// builds on — Products, Categories, Inventory, Orders, Sales, Customers,
/// Suppliers, Purchases, Returns, Employees, Reports, Audit history. Takes
/// an already-paginated `rows` (never "all records," §26) and renders:
///  - loading → skeleton rows
///  - error → `AppErrorState` with retry
///  - empty → `AppEmptyState`
///  - otherwise → a real `DataTable` on desktop/tablet (horizontal scroll
///    only if the columns genuinely don't fit the available width), or a
///    card-per-row list on mobile (§11: "mobile-friendly alternatives",
///    never a table simply overflowing the screen).
///
/// Sorting/filtering/pagination are all *reported* via callbacks — this
/// widget does no data fetching or in-memory sorting itself; that's a
/// future module's repository's job (§26's server-side requirement).
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.idOf,
    this.rowActionsBuilder,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle = 'No records yet',
    this.emptyDescription,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.selectable = false,
    this.selectedIds = const <Object>{},
    this.onSelectionChanged,
    this.onRowTap,
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final Object Function(T item) idOf;
  final Widget Function(BuildContext context, T item)? rowActionsBuilder;

  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  final String emptyTitle;
  final String? emptyDescription;

  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending)? onSort;

  final bool selectable;
  final Set<Object> selectedIds;
  final void Function(Set<Object> selected)? onSelectionChanged;
  final void Function(T item)? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (loading) return _LoadingRows(columnCount: columns.length);

    if (errorMessage != null) {
      return AppErrorState(message: errorMessage!, onRetry: onRetry);
    }

    if (rows.isEmpty) {
      return AppEmptyState(icon: Icons.table_rows_outlined, title: emptyTitle, description: emptyDescription);
    }

    final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    return isMobile ? _CardList<T>(table: this) : _DesktopTable<T>(table: this);
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows({required this.columnCount});
  final int columnCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(6, (_) => AppSkeletonRow(columns: columnCount.clamp(2, 5))),
    );
  }
}

class _DesktopTable<T> extends StatelessWidget {
  const _DesktopTable({required this.table});
  final AppDataTable<T> table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final dataTable = DataTable(
      showCheckboxColumn: table.selectable,
      sortColumnIndex: table.sortColumnIndex,
      sortAscending: table.sortAscending,
      headingRowColor: WidgetStateProperty.all(colors.background),
      headingTextStyle: AppTypography.tableHeader.copyWith(color: colors.textSecondary),
      dataTextStyle: AppTypography.tableText.copyWith(color: colors.textPrimary),
      dividerThickness: 1,
      columns: [
        for (var i = 0; i < table.columns.length; i++)
          DataColumn(
            label: Text(table.columns[i].label),
            numeric: table.columns[i].numeric,
            onSort: table.columns[i].sortable && table.onSort != null
                ? (columnIndex, ascending) => table.onSort!(columnIndex, ascending)
                : null,
          ),
        if (table.rowActionsBuilder != null) const DataColumn(label: Text('')),
      ],
      rows: [
        for (final item in table.rows)
          DataRow(
            selected: table.selectedIds.contains(table.idOf(item)),
            onSelectChanged: table.selectable && table.onSelectionChanged != null
                ? (selected) => _toggleSelection(item, selected ?? false)
                : (table.onRowTap != null ? (_) => table.onRowTap!(item) : null),
            cells: [
              for (final column in table.columns) DataCell(column.cellBuilder(context, item)),
              if (table.rowActionsBuilder != null) DataCell(table.rowActionsBuilder!(context, item)),
            ],
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bordered = Container(
          decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: AppRadius.mdRadius),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: colors.border),
            child: dataTable,
          ),
        );

        // Always inside a horizontal scroller (§11: "only if the columns
        // genuinely don't fit" — found by measurement, not by guessing).
        // This used to branch on a hand-estimated `preferredWidth` and skip
        // the scroller when the estimate said the table would fit; running
        // it for real (Suppliers/Purchases at desktop width) showed the
        // estimate routinely undershoots `DataTable`'s own real column
        // sizing (e.g. a long header like "Outstanding Balance" widens its
        // column more than a flat per-column guess accounts for) — when
        // that happened, `SizedBox(width: double.infinity)` gave the table
        // a *tight* width instead of room to size itself, and `DataTable`
        // doesn't shrink its cells' content to fit, it overflows them.
        // `minWidth: constraints.maxWidth` (not a fixed width) keeps a
        // narrow table stretched to fill the available space exactly as
        // before; a wide table now sizes itself naturally and scrolls
        // instead of being squeezed.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: bordered,
          ),
        );
      },
    );
  }

  void _toggleSelection(T item, bool selected) {
    final id = table.idOf(item);
    final next = Set<Object>.from(table.selectedIds);
    selected ? next.add(id) : next.remove(id);
    table.onSelectionChanged?.call(next);
  }
}

/// Mobile fallback — one card per row instead of a squeezed/scrolled table
/// (§11's explicit requirement).
class _CardList<T> extends StatelessWidget {
  const _CardList({required this.table});
  final AppDataTable<T> table;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        for (final item in table.rows)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border.all(color: colors.border),
              borderRadius: AppRadius.mdRadius,
            ),
            child: InkWell(
              onTap: table.onRowTap != null ? () => table.onRowTap!(item) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: table.columns.first.cellBuilder(context, item)),
                      if (table.rowActionsBuilder != null) table.rowActionsBuilder!(context, item),
                    ],
                  ),
                  for (final column in table.columns.skip(1))
                    if (column.showInMobileCard)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(column.label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                            column.cellBuilder(context, item),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
