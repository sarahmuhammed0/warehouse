import 'package:flutter/material.dart';

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
    this.primaryAction,
    this.secondaryActions,
    this.searchBar,
    this.filterBar,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final List<BreadcrumbItem>? breadcrumbs;
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
    required this.primaryAction,
    required this.secondaryActions,
    required this.colors,
  });

  final String title;
  final String? subtitle;
  final Widget? primaryAction;
  final List<Widget>? secondaryActions;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
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
