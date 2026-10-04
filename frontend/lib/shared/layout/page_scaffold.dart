import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'breadcrumbs.dart';
import 'responsive/responsive_layout.dart';

/// The standard page layout (§10) every module builds its screens on:
/// title/subtitle/breadcrumbs → primary+secondary actions → an optional
/// search/filter row → the content area. Deliberately does not know about
/// loading/empty/error — `body` is just a widget, and a feature passes
/// `AppLoading.page()` / `AppEmptyState(...)` / `AppErrorState(...)` /
/// `AppDataTable(...)` for it depending on its own state. That keeps this
/// widget decoupled from any particular state-management shape.
///
/// Page padding is deliberately modest: on desktop the shell already
/// insets the content area, and doubling both gutters pushes every table
/// away from the edge it should be using.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.titleWidget,
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

  /// Renders in place of [title] when a page needs a headline richer than
  /// one string — the dashboards' two-tone greeting. [title] is still
  /// required and still carries the page's name for anything reading the
  /// page semantically rather than looking at it.
  final Widget? titleWidget;

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
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.md,
        isMobile ? AppSpacing.lg : AppSpacing.xs,
        isMobile ? AppSpacing.lg : AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.xl,
        children: [
          if (breadcrumbs != null) Breadcrumbs(items: breadcrumbs!),
          _HeaderRow(
            title: title,
            titleWidget: titleWidget,
            subtitle: subtitle,
            showBackButton: showBackButton,
            backFallbackRoute: backFallbackRoute,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            colors: colors,
          ),
          if (searchBar != null || filterBar != null)
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
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
    required this.titleWidget,
    required this.subtitle,
    required this.showBackButton,
    required this.backFallbackRoute,
    required this.primaryAction,
    required this.secondaryActions,
    required this.colors,
  });

  final String title;
  final Widget? titleWidget;
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
        titleWidget ??
            Text(title, style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppTypography.body.copyWith(color: colors.textMuted)),
        ],
      ],
    );

    final titleBlock = showBackButton
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _BackButton(fallbackRoute: backFallbackRoute),
              ),
              const SizedBox(width: AppSpacing.md),
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
        spacing: AppSpacing.md,
        children: [
          titleBlock,
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The title takes two thirds, the actions up to one third.
        //
        // The actions used to be a bare `Wrap` here, with no width bound. A Wrap
        // given unbounded width never wraps — it lays its children out on one
        // line as wide as they need — so between 600px (where the Column branch
        // above stops) and whatever the buttons happen to total, the row simply
        // overflowed and Flutter painted its striped banner across the header.
        // A browser pane beside an editor is exactly that width.
        //
        // `Flexible` gives the Wrap a real maximum, so it wraps onto a second
        // line instead, and `WrapAlignment.end` keeps the buttons against the
        // right edge where they have always sat.
        Expanded(flex: 2, child: titleBlock),
        if (actions.isNotEmpty)
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions,
            ),
          ),
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
    final colors = context.colors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final icon = isRtl ? Icons.arrow_forward : Icons.arrow_back;

    return Material(
      color: colors.surface,
      shape: CircleBorder(side: BorderSide(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else if (fallbackRoute != null) {
            context.go(fallbackRoute!);
          }
        },
        child: Tooltip(
          message: MaterialLocalizations.of(context).backButtonTooltip,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
