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
/// `AppShell`. Supports a collapsed desktop state (icons only) and renders
/// as a `Drawer` on mobile/tablet via the same widget (the caller decides
/// which container it sits in — this widget only renders its own content).
///
/// **Why this is still a labelled sidebar.** The design references put a
/// short pill nav across the header, which works for the six destinations
/// they show. This product has seventeen business modules, gated per role
/// and per business type, and §8 is explicit that no route may be dropped
/// and no second navigation menu may be added. So the sidebar keeps its
/// labels and takes on the reference's *visual* language instead — a
/// floating white panel, a brand lockup, and a filled pill for the active
/// entry.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.currentPath,
    required this.brandLabel,
    this.brandSubtitle,
    this.brandIcon,
    this.collapsed = false,
    this.onCollapseToggle,
    this.onNavigate,
    this.footer,
  });

  final List<NavItem> items;
  final String currentPath;
  final String brandLabel;

  /// The line under the brand name — how the System Admin area identifies
  /// itself as platform-level rather than as one more business (§3).
  final String? brandSubtitle;

  /// Overrides the initial-letter brand tile. The System Admin area passes
  /// a shield so the two shells are told apart at a glance.
  final IconData? brandIcon;

  final bool collapsed;
  final VoidCallback? onCollapseToggle;

  /// Fired after a nav item is selected — lets a `Drawer` host close
  /// itself once navigation has happened.
  final VoidCallback? onNavigate;

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
            _Brand(
              label: brandLabel,
              subtitle: brandSubtitle,
              icon: brandIcon,
              collapsed: collapsed,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  for (final item in items)
                    _NavTile(
                      key: ValueKey('nav:${item.route}'),
                      item: item,
                      label: item.labelBuilder(l10n),
                      selected: currentPath == item.route || currentPath.startsWith('${item.route}/'),
                      collapsed: collapsed,
                      onTap: () {
                        context.go(item.route);
                        onNavigate?.call();
                      },
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

/// The brand lockup — a rounded-square accent tile plus the wordmark. On a
/// business shell the tile carries the business's own initial; the System
/// Admin area passes an icon instead.
class _Brand extends StatelessWidget {
  const _Brand({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.collapsed,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final tile = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadius.smRadius),
      child: icon != null
          ? Icon(icon, size: 20, color: colors.onPrimary)
          : Text(
              label.isNotEmpty ? label[0].toUpperCase() : 'W',
              style: AppTypography.cardTitle.copyWith(color: colors.onPrimary, fontSize: 17),
            ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        collapsed ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          tile,
          if (!collapsed) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                ],
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
    super.key,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.selectedBg : Colors.transparent,
        borderRadius: AppRadius.mdRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.surfaceMuted,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : AppSpacing.md,
              vertical: 10,
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
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Align(
        alignment: collapsed ? Alignment.center : AlignmentDirectional.centerStart,
        child: Material(
          color: colors.surfaceMuted,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Tooltip(
              message: collapsed ? 'Expand' : 'Collapse',
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, size: 18, color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
