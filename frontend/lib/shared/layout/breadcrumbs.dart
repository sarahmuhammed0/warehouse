import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class BreadcrumbItem {
  const BreadcrumbItem(this.label, {this.onTap});
  final String label;
  final VoidCallback? onTap;
}

/// Optional breadcrumb trail (§10/§6). A `Row` naturally reverses its
/// visual order under RTL `Directionality` — no manual mirroring needed
/// here (§21).
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({super.key, required this.items});

  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Icon(Icons.chevron_right, size: 16, color: colors.textMuted),
            ),
          _Crumb(item: items[i], isLast: i == items.length - 1),
        ],
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.item, required this.isLast});

  final BreadcrumbItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.caption.copyWith(
      color: isLast ? colors.textPrimary : colors.textMuted,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );

    if (item.onTap == null || isLast) return Text(item.label, style: style);

    return InkWell(
      onTap: item.onTap,
      child: Text(item.label, style: style.copyWith(decoration: TextDecoration.underline)),
    );
  }
}
