import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../search/global_search_bar.dart';

/// Reusable header (§9). Everything past the page-context title is a
/// placeholder slot for functionality that doesn't exist yet — global
/// search has no backend to query, notifications/account have no signed-in
/// user. The slots exist and are wired into the layout now so Phase 2 fills
/// them in without touching this file's structure.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

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
                _TopBarIcon(
                  icon: Icons.account_circle_outlined,
                  tooltip: l10n.account,
                  onTap: () {}, // Phase 2: opens the real account menu.
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
