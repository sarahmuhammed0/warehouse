import 'package:flutter/widgets.dart';

/// One column definition for [AppDataTable]. Generic over the row type `T`
/// so the same table foundation serves Products, Orders, Customers, etc.
/// (§11) without a per-module table implementation.
class AppTableColumn<T> {
  const AppTableColumn({
    required this.label,
    required this.cellBuilder,
    this.sortable = false,
    this.width,
    this.numeric = false,
    this.showInMobileCard = true,
  });

  final String label;
  final Widget Function(BuildContext context, T item) cellBuilder;

  /// UI-only — clicking the header reports the intent via
  /// `AppDataTable.onSort`; actual sorting happens server-side (§26) once a
  /// module is connected to a real API.
  final bool sortable;

  final double? width;
  final bool numeric;

  /// The first column is always shown on the mobile card layout as the
  /// card's title; set false on a column that's redundant there (Phase 1
  /// has no real columns yet, but future modules will).
  final bool showInMobileCard;
}
