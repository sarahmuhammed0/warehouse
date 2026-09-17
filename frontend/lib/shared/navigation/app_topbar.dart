import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../l10n/generated/app_localizations.dart';
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
                Text(
                  pageContext,
                  style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
                ),
                const Spacer(),
                if (showSearch && context.isDesktopWidth) ...[
                  const SizedBox(
                    width: 280,
                    child: GlobalSearchBar(),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                _TopBarIcon(
                  icon: Icons.notifications_outlined,
                  tooltip: l10n.notifications,
                  onTap: () => _showNotificationsPlaceholder(context, l10n),
                ),
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

  void _showNotificationsPlaceholder(BuildContext context, AppLocalizations l10n) {
    showMenu<void>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 60, 16, 0),
      items: [PopupMenuItem<void>(enabled: false, child: Text(l10n.noNotificationsYet))],
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

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: context.colors.textSecondary),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

extension on BuildContext {
  bool get isDesktopWidth => MediaQuery.sizeOf(this).width >= 900;
}
