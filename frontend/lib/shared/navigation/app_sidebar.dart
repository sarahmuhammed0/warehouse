import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'nav_items.dart';

/// One sidebar widget, reused for both the business app and the System
/// Admin area (different `items` lists, same visual language) — see
/// `AppShell`/`AdminShell`. Supports a collapsed desktop state (icons only)
/// and renders as a `Drawer` on mobile/tablet via the same widget (the
/// caller decides which container it sits in — this widget only renders
/// its own content).
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.currentPath,
    required this.brandLabel,
    this.collapsed = false,
    this.onCollapseToggle,
    this.footer,
  });

  final List<NavItem> items;
  final String currentPath;
  final String brandLabel;
  final bool collapsed;
  final VoidCallback? onCollapseToggle;

  /// Placeholder slot for the future user/account area (§8: "user/account
  /// area placeholder") — not real user data in Phase 1.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(label: brandLabel, collapsed: collapsed),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  for (final item in items)
                    _NavTile(
                      item: item,
                      label: item.labelBuilder(l10n),
                      selected: currentPath == item.route || currentPath.startsWith('${item.route}/'),
                      collapsed: collapsed,
                      onTap: () => context.go(item.route),
                    ),
                ],
              ),
            ),
            if (onCollapseToggle != null)
              _CollapseToggle(collapsed: collapsed, onTap: onCollapseToggle!),
            ?footer,
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.label, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadius.smRadius),
            child: Text(
              label.isNotEmpty ? label[0].toUpperCase() : 'W',
              style: AppTypography.cardTitle.copyWith(color: colors.onPrimary),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final NavItem item;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.primary : colors.textSecondary;

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      child: Material(
        color: selected ? colors.selectedBg : Colors.transparent,
        borderRadius: AppRadius.mdRadius,
        child: InkWell(
          borderRadius: AppRadius.mdRadius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: collapsed
                ? Center(child: Icon(item.icon, size: 20, color: fg))
                : Row(
                    children: [
                      Icon(item.icon, size: 20, color: fg),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.navLabel.copyWith(
                            color: fg,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: label, child: tile) : tile;
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // chevron_left/right are literal glyphs, not auto-mirrored by
    // Directionality (§21) — flipped by hand so the arrow always points
    // toward where the sidebar content will expand to.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final icon = collapsed == isRtl ? Icons.chevron_left : Icons.chevron_right;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: colors.textMuted),
        tooltip: collapsed ? 'Expand' : 'Collapse',
      ),
    );
  }
}
