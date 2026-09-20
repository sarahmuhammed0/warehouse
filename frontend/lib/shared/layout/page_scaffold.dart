import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'breadcrumbs.dart';
import 'responsive/responsive_layout.dart';

/// The standard page layout (§10) every future module builds its screens
/// on: title/subtitle/breadcrumbs → primary+secondary actions → an optional
/// search/filter row → the content area. Deliberately does not know about
/// loading/empty/error — `body` is just a widget, and a feature passes
/// `AppLoading.page()` / `AppEmptyState(...)` / `AppErrorState(...)` /
/// `AppDataTable(...)` for it depending on its own state. That keeps this
/// widget decoupled from any particular state-management shape.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.breadcrumbs,
    this.showBackButton = false,
    this.backFallbackRoute,
    this.primaryAction,
    this.secondaryActions,
    this.searchBar,
    this.filterBar,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final List<BreadcrumbItem>? breadcrumbs;

  /// Detail pages (§ global back-navigation rule) pass this instead of
  /// [breadcrumbs] — pops the real navigation stack (preserving whatever
  /// state the previous list/search screen had) rather than replacing the
  /// location, which is what a breadcrumb's `context.go` back to a bare
  /// list route would otherwise reset.
  final bool showBackButton;

  /// Only consulted when [showBackButton] is true and there's nothing left
  /// to pop (e.g. a deep link straight to this detail page) — go_router's
  /// `context.pop()` cannot recover from an empty stack on its own.
  final String? backFallbackRoute;
  final Widget? primaryAction;
  final List<Widget>? secondaryActions;
  final Widget? searchBar;
  final Widget? filterBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = context.isMobile;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          if (breadcrumbs != null) Breadcrumbs(items: breadcrumbs!),
          _HeaderRow(
            title: title,
            subtitle: subtitle,
            showBackButton: showBackButton,
            backFallbackRoute: backFallbackRoute,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            colors: colors,
          ),
          if (searchBar != null || filterBar != null)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?searchBar, ?filterBar],
            ),
          body,
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    required this.subtitle,
    required this.showBackButton,
    required this.backFallbackRoute,
    required this.primaryAction,
    required this.secondaryActions,
    required this.colors,
  });

  final String title;
  final String? subtitle;
  final bool showBackButton;
  final String? backFallbackRoute;
  final Widget? primaryAction;
  final List<Widget>? secondaryActions;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final titleText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AppTypography.body.copyWith(color: colors.textMuted)),
        ],
      ],
    );

    final titleBlock = showBackButton
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackButton(fallbackRoute: backFallbackRoute),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: titleText),
            ],
          )
        : titleText;

    final actions = [...?secondaryActions, ?primaryAction];

    if (context.isMobile && actions.isNotEmpty) {
      // Actions wrap below the title on narrow screens rather than
      // squeezing into the same row as a long page title (§5).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          titleBlock,
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        if (actions.isNotEmpty)
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
      ],
    );
  }
}

/// The global detail-page back control (replaces per-screen breadcrumb
/// "parent > page" trails). Pops the real Navigator stack so the previous
/// list/search screen reappears exactly as it was — filters, pagination,
/// scroll position — since it was never rebuilt, only covered. `context.go`
/// cannot do this: it replaces the location with a fresh instance of the
/// target route, discarding that state, which is exactly the bug this
/// button exists to avoid. Manually flips the glyph for RTL rather than
/// relying on it being auto-mirrored, matching `AppSidebar`'s
/// `_CollapseToggle` (`Icons.arrow_back`/`arrow_forward` are literal glyphs,
/// not directional-aware by themselves).
class _BackButton extends StatelessWidget {
  const _BackButton({required this.fallbackRoute});

  final String? fallbackRoute;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final icon = isRtl ? Icons.arrow_forward : Icons.arrow_back;

    return IconButton(
      icon: Icon(icon),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else if (fallbackRoute != null) {
          context.go(fallbackRoute!);
        }
      },
    );
  }
}
