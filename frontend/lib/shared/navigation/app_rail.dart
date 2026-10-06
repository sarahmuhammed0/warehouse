import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'nav_indicator.dart';
import 'nav_indicators_provider.dart';
import 'nav_items.dart';

/// The slim icon rail down the side of the desktop shell — the reference
/// design's second navigation surface, carrying the modules the header's
/// pill bar does not (see `splitNavItems`).
///
/// Icon-only by design: the rail exists so the header stays short enough to
/// read at a glance, and putting the labels back would just be the old
/// sidebar at half the width. Every item carries a tooltip, so the label is
/// one hover away and screen readers get it from the same string.
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.items,
    required this.currentPath,
    this.footer = const [],
  });

  final List<NavItem> items;
  final String currentPath;

  /// Rail-bottom controls that are not navigation — theme, sign out.
  final List<Widget> footer;

  static const double width = 68;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: context.colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  for (final item in items)
                    _RailButton(
                      key: ValueKey('nav:${item.route}'),
                      route: item.route,
                      icon: item.icon,
                      label: item.labelBuilder(l10n),
                      selected: currentPath == item.route ||
                          currentPath.startsWith('${item.route}/'),
                      onTap: () => context.go(item.route),
                    ),
                ],
              ),
            ),
            if (footer.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Divider(height: 1, color: context.colors.border),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(children: footer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One rail destination. Selected is a filled brand circle — the reference's
/// own treatment, and the one state strong enough to read at this size with
/// no label beside it.
class _RailButton extends ConsumerWidget {
  const _RailButton({
    super.key,
    required this.route,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String route;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final indicator = ref.watch(navIndicatorProvider(route));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Material(
          color: selected ? colors.primary : Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: selected ? null : colors.surfaceMuted,
            child: SizedBox(
              height: 40,
              child: NavIndicatorBadge(
                indicator: indicator,
                semanticLabel: label,
                // A dot, not a number: a count inside a 20px icon button is
                // unreadable, and the tooltip already names the destination.
                showCount: false,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? colors.onPrimary : colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rail-footer control that is an action rather than a destination.
class RailActionButton extends StatelessWidget {
  const RailActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 3),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            hoverColor: colors.surfaceMuted,
            child: SizedBox(
              height: 40,
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
