import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_mode.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../features/notifications/data/notification_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_icon_chip.dart';
import '../search/global_search_bar.dart';
import 'nav_items.dart';

/// The application header (§7/§9) — brand lockup, the primary destinations
/// as a pill bar, and the account/notification controls.
///
/// This is the shell's main navigation surface on desktop; the icon rail
/// beside it carries the remaining modules (`splitNavItems`). On compact
/// widths the pill bar and the brand collapse away entirely and the header
/// falls back to a menu button plus the current page's name, because a
/// scrolling pill bar on a phone is worse than the drawer it would replace.
class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.pageContext,
    this.navItems = const [],
    this.currentPath = '',
    this.brandLabel,
    this.brandSubtitle,
    this.brandIcon,
    this.onMenuTap,
    this.showSearch = true,
  });

  /// Current section name (e.g. the active nav item's label) — §9's "page
  /// context" slot, shown when there is no pill bar to say it instead.
  final String pageContext;

  /// The destinations shown as pills. Empty on compact layouts.
  final List<NavItem> navItems;
  final String currentPath;

  final String? brandLabel;
  final String? brandSubtitle;
  final IconData? brandIcon;

  /// Present only when the sidebar is a Drawer (mobile/tablet) — opens it.
  final VoidCallback? onMenuTap;

  final bool showSearch;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authControllerProvider);
    final accountName = authState is AuthAuthenticated ? authState.account.name : null;
    final width = MediaQuery.sizeOf(context).width;
    final showNav = navItems.isNotEmpty;
    final showInlineSearch = showSearch && width >= 1500;

    return Material(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                if (onMenuTap != null) ...[
                  _HeaderCircle(
                    icon: Icons.menu,
                    onTap: onMenuTap,
                    tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                if (brandLabel != null)
                  _Brand(label: brandLabel!, subtitle: brandSubtitle, icon: brandIcon)
                else
                  Flexible(
                    child: Text(
                      pageContext,
                      style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (AppModeConfig.isDemo) ...[
                  const SizedBox(width: AppSpacing.sm),
                  // §10 of the frontend-demo-mode brief: small, non-intrusive,
                  // always visible — so a demo-mode action is never mistaken
                  // for something saved to a real backend.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.warningBg,
                      borderRadius: AppRadius.pillRadius,
                    ),
                    child: Text(
                      l10n.demoModeIndicator,
                      style: AppTypography.statusBadge.copyWith(color: colors.warning),
                    ),
                  ),
                ],
                if (showNav)
                  Expanded(
                    child: Center(
                      child: _NavPills(
                        items: navItems,
                        currentPath: currentPath,
                        l10n: l10n,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (showInlineSearch) ...[
                  SizedBox(
                    width: 260,
                    child: GlobalSearchBar(onSubmitted: (q) => _search(context, q)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ] else if (showSearch) ...[
                  _HeaderCircle(
                    icon: Icons.search,
                    tooltip: l10n.search,
                    onTap: () => context.push(AppRoutes.search),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                _NotificationBell(l10n: l10n),
                const SizedBox(width: AppSpacing.sm),
                _AccountMenu(
                  accountName: accountName,
                  logoutLabel: l10n.logout,
                  onLogout: () => ref.read(authControllerProvider.notifier).logout(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _search(BuildContext context, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    context.push('${AppRoutes.search}?q=${Uri.encodeQueryComponent(trimmed)}');
  }
}

/// The brand lockup — accent tile plus wordmark, and an identity line under
/// it where one applies (the System Admin area says so there).
class _Brand extends StatelessWidget {
  const _Brand({required this.label, required this.subtitle, required this.icon});

  final String label;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
        ),
        const SizedBox(width: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sectionTitle.copyWith(color: colors.primary),
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
    );
  }
}

/// The header's pill bar. Scrolls rather than wraps if the window is too
/// narrow to hold every primary destination — a header that changes height
/// as the window resizes is worse than one that scrolls.
class _NavPills extends StatelessWidget {
  const _NavPills({required this.items, required this.currentPath, required this.l10n});

  final List<NavItem> items;
  final String currentPath;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _NavPill(
                key: ValueKey('nav:${item.route}'),
                label: item.labelBuilder(l10n),
                selected: currentPath == item.route || currentPath.startsWith('${item.route}/'),
                onTap: () => context.go(item.route),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      // The selected pill is a white chip lifted off the muted track, the
      // way the reference marks the current section — not a filled accent
      // block, which would shout louder than the page's primary action.
      color: selected ? colors.surface : Colors.transparent,
      borderRadius: AppRadius.pillRadius,
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 1 : 0,
      shadowColor: colors.shadow.withValues(alpha: 0.18),
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 9),
          child: Text(
            label,
            style: AppTypography.button.copyWith(
              color: selected ? colors.textPrimary : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The header's circular control chrome. Shared by the menu button, the
/// search shortcut and the two popup triggers, so they are all one size.
class _HeaderCircle extends StatelessWidget {
  const _HeaderCircle({this.icon, this.onTap, this.tooltip, this.child})
      : assert(icon != null || child != null, 'a header circle needs something to show');

  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Replaces the plain icon — used by the bell, which needs its unread
  /// count layered on top.
  final Widget? child;

  static const double diameter = 40;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: child ?? Icon(icon, size: 19, color: colors.textSecondary),
    );

    if (onTap == null) return content;

    final tappable = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: content,
    );

    return tooltip == null ? tappable : Tooltip(message: tooltip!, child: tappable);
  }
}

enum _AccountAction { logout }

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.accountName, required this.logoutLabel, required this.onLogout});

  final String? accountName;
  final String logoutLabel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<_AccountAction>(
      key: const ValueKey('accountMenu'),
      tooltip: accountName ?? 'Account',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accountName != null)
            AppAvatar(label: accountName!, size: 38, tone: colors.primary)
          else
            // No signed-in name to build initials from — the generic
            // account glyph is the honest fallback, and it is also what
            // the header shows before the session resolves.
            Icon(Icons.account_circle_outlined, size: 34, color: colors.textSecondary),
          Icon(Icons.expand_more, size: 18, color: colors.textMuted),
        ],
      ),
      onSelected: (action) {
        if (action == _AccountAction.logout) onLogout();
      },
      itemBuilder: (context) => [
        if (accountName != null)
          PopupMenuItem<_AccountAction>(
            enabled: false,
            child: Text(
              accountName!,
              style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
            ),
          ),
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.logout,
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Text(logoutLabel),
            ],
          ),
        ),
      ],
    );
  }
}

/// Real notification center (spec §29/§31) — low/out-of-stock entries are
/// derived live from real product data (`NotificationsController`); the
/// badge count and dropdown are both driven by that same provider, not a
/// static placeholder.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return PopupMenuButton<String>(
      tooltip: l10n.notifications,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      icon: _HeaderCircle(
        child: Badge(
          label: Text('$unreadCount'),
          isLabelVisible: unreadCount > 0,
          backgroundColor: colors.error,
          child: Icon(Icons.notifications_outlined, size: 19, color: colors.textSecondary),
        ),
      ),
      itemBuilder: (context) => [
        if (notifications.isEmpty)
          PopupMenuItem<String>(enabled: false, child: Text(l10n.noNotificationsYet))
        else ...[
          for (final n in notifications.take(6))
            PopupMenuItem<String>(
              value: n.id,
              onTap: () {
                ref.read(notificationsProvider.notifier).markRead(n.id);
                // ...and go to what it is about. `PopupMenuItem.onTap`
                // fires after the menu closes, so pushing here is safe.
                final route = n.targetRoute;
                if (route != null) context.push(route);
              },
              child: SizedBox(
                width: 280,
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: n.isUnread ? colors.primary : Colors.transparent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(n.title, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                          Text(
                            n.body,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (unreadCount > 0) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'mark-all-read',
              onTap: () => ref.read(notificationsProvider.notifier).markAllRead(),
              child: Text(l10n.markAllRead),
            ),
          ],
        ],
      ],
    );
  }
}
