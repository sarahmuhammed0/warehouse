import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_elevation.dart';
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
/// Visually the table is one white surface with air in it: quiet small-caps
/// headers, tall comfortable rows, a hover tint, and **no vertical rules
/// at all** — §12's "avoid visually heavy grid lines, use whitespace
/// instead". Columns are separated by spacing, which is what makes a
/// twelve-column products table still readable.
///
/// Sorting/filtering/pagination are all *reported* via callbacks — this
/// widget does no data fetching or in-memory sorting itself; that's a
/// module's repository's job (§26's server-side requirement).
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
    if (loading) return _Surface(child: _LoadingRows(columnCount: columns.length));

    if (errorMessage != null) {
      return _Surface(child: AppErrorState(message: errorMessage!, onRetry: onRetry));
    }

    if (rows.isEmpty) {
      return _Surface(
        child: AppEmptyState(
          icon: Icons.table_rows_outlined,
          title: emptyTitle,
          description: emptyDescription,
        ),
      );
    }

    final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    return isMobile ? _CardList<T>(table: this) : _Surface(child: _DesktopTable<T>(table: this));
  }
}

/// The white panel a table (or its loading/empty/error stand-in) sits on.
/// Same radius and lift as [AppCard] — a table is a content surface like
/// any other, and the two must not differ.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.border),
        boxShadow: AppElevation.cardShadow(colors, Theme.of(context).brightness),
      ),
      child: ClipRRect(borderRadius: AppRadius.cardRadius, child: child),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows({required this.columnCount});
  final int columnCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: List.generate(6, (_) => AppSkeletonRow(columns: columnCount.clamp(2, 5))),
      ),
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
      headingRowColor: WidgetStateProperty.all(colors.surfaceMuted),
      headingTextStyle: AppTypography.tableHeader.copyWith(color: colors.textMuted),
      dataTextStyle: AppTypography.tableText.copyWith(color: colors.textPrimary),
      headingRowHeight: 48,
      dataRowMinHeight: 54,
      dataRowMaxHeight: 64,
      horizontalMargin: AppSpacing.xl,
      columnSpacing: AppSpacing.xxl,
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
            // Hover and selection are the only row decoration — §12's
            // "hover state, selected state where needed".
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return colors.accentSoft;
              if (states.contains(WidgetState.hovered)) return colors.surfaceMuted;
              return null;
            }),
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
            child: Theme(
              // The divider is the single horizontal rule under the header
              // and between rows; kept at the faintest border token so the
              // table reads as banded whitespace rather than as a grid.
              data: Theme.of(context).copyWith(dividerColor: colors.border),
              child: dataTable,
            ),
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
/// (§11's explicit requirement, and §26's "tables may become card/list
/// representations on small screens").
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
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: AppRadius.lgRadius,
              border: Border.all(color: colors.border),
              boxShadow: AppElevation.cardShadow(colors, Theme.of(context).brightness),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: table.onRowTap != null ? () => table.onRowTap!(item) : null,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DefaultTextStyle.merge(
                              style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                              child: table.columns.first.cellBuilder(context, item),
                            ),
                          ),
                          if (table.rowActionsBuilder != null) table.rowActionsBuilder!(context, item),
                        ],
                      ),
                      for (final column in table.columns.skip(1))
                        if (column.showInMobileCard)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            // Both sides Flexible: neither the label nor the
                            // value is bounded otherwise, so one long cell (a
                            // full customer name, a formatted date) overflowed
                            // the card on a phone. Found by running the
                            // dashboard's drill-downs at 390px.
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    column.label,
                                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Flexible(child: column.cellBuilder(context, item)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
