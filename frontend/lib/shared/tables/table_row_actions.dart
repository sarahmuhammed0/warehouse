import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class RowAction {
  const RowAction({required this.label, required this.icon, required this.onTap, this.destructive = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

/// The "⋮" per-row action menu (§11/§42/§43 — every table's Actions column:
/// view/edit/history/delete, or order-specific PDF/print/return/cancel).
/// One widget for every future table so the menu always looks and behaves
/// the same.
class TableRowActions extends StatelessWidget {
  const TableRowActions({super.key, required this.actions});

  final List<RowAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    return PopupMenuButton<RowAction>(
      icon: Icon(Icons.more_vert, color: colors.textSecondary, size: 20),
      onSelected: (action) => action.onTap(),
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<RowAction>(
            value: action,
            child: Row(
              children: [
                Icon(action.icon, size: 18, color: action.destructive ? colors.error : colors.textSecondary),
                const SizedBox(width: 10),
                Text(action.label, style: TextStyle(color: action.destructive ? colors.error : colors.textPrimary)),
              ],
            ),
          ),
      ],
    );
  }
}
