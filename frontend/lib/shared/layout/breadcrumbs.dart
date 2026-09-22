import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class BreadcrumbItem {
  const BreadcrumbItem(this.label, {this.onTap});
  final String label;
  final VoidCallback? onTap;
}

/// Optional breadcrumb trail (§10/§6). A `Wrap` reverses the *order* of
/// the crumbs under RTL `Directionality` on its own — but the separator
/// glyph between them does not follow, because `Icons.chevron_right` is a
/// literal right-pointing chevron, not a directional-aware icon. Under
/// Arabic or Kurdish the trail therefore read right-to-left while its
/// arrows still pointed right, i.e. backwards. Picked explicitly here, the
/// same way `PaginationBar` and the sidebar's collapse toggle do it (§25).
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({super.key, required this.items});

  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final separator = isRtl ? Icons.chevron_left : Icons.chevron_right;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Icon(separator, size: 16, color: colors.textMuted),
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
