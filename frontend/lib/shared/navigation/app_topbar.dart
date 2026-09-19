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
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../search/global_search_bar.dart';

/// Reusable header (§9). Global search has no backend to query yet
/// (Phase 3+); the account menu is real as of Phase 2 — shows the signed-in
/// user's name and a working Logout action, the one place in the shell
/// that calls `AuthController.logout()`.
class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.pageContext,
    this.onMenuTap,
    this.showSearch = true,
  });

  /// Current section name (e.g. the active nav item's label) — §9's "page
  /// context" slot.
  final String pageContext;

  /// Present only when the sidebar is a Drawer (mobile/tablet) — opens it.
  final VoidCallback? onMenuTap;

  final bool showSearch;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authControllerProvider);
    final accountName = authState is AuthAuthenticated ? authState.account.name : null;

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
                  IconButton(icon: const Icon(Icons.menu), onPressed: onMenuTap),
                  const SizedBox(width: AppSpacing.sm),
                ],
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: colors.warningBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      l10n.demoModeIndicator,
                      style: AppTypography.statusBadge.copyWith(color: colors.warning),
                    ),
                  ),
                ],
                const Spacer(),
                if (showSearch && context.isDesktopWidth) ...[
                  SizedBox(
                    width: 280,
                    child: GlobalSearchBar(
                      onSubmitted: (query) {
                        final trimmed = query.trim();
                        if (trimmed.isEmpty) return;
                        context.push('${AppRoutes.search}?q=${Uri.encodeQueryComponent(trimmed)}');
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                _NotificationBell(l10n: l10n),
                const SizedBox(width: AppSpacing.xs),
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
      tooltip: accountName ?? 'Account',
      icon: Icon(Icons.account_circle_outlined, color: colors.textSecondary),
      onSelected: (action) {
        if (action == _AccountAction.logout) onLogout();
      },
      itemBuilder: (context) => [
        if (accountName != null)
          PopupMenuItem<_AccountAction>(
            enabled: false,
            child: Text(accountName!, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
          ),
        PopupMenuItem<_AccountAction>(
          value: _AccountAction.logout,
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: colors.textSecondary),
              const SizedBox(width: 10),
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
      icon: Badge(
        label: Text('$unreadCount'),
        isLabelVisible: unreadCount > 0,
        child: Icon(Icons.notifications_outlined, color: colors.textSecondary),
      ),
      itemBuilder: (context) => [
        if (notifications.isEmpty)
          PopupMenuItem<String>(enabled: false, child: Text(l10n.noNotificationsYet))
        else ...[
          for (final n in notifications.take(6))
            PopupMenuItem<String>(
              value: n.id,
              onTap: () => ref.read(notificationsProvider.notifier).markRead(n.id),
              child: SizedBox(
                width: 260,
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: n.isUnread ? colors.primary : Colors.transparent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(n.title, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                          Text(n.body, style: AppTypography.caption.copyWith(color: colors.textMuted), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

extension on BuildContext {
  bool get isDesktopWidth => MediaQuery.sizeOf(this).width >= 900;
}
