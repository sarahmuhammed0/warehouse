import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_elevation.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Base surface primitive (architecture §27/§16) — every other card in the
/// shared library (`shared/dashboard/*`) composes this one instead of
/// redefining radius/padding/elevation.
///
/// The FactoryOS surface is a generously rounded white panel lifted off a
/// near-white canvas by a soft shadow, not a box drawn with a border. That
/// distinction is the whole reason this widget exists: get it right once
/// here and every list, dashboard and form in the app inherits it.
///
/// The header slots ([leading], [title], [subtitle], [actions]) are all
/// optional and compose into the reference layout —
/// `[icon chip] Title / subtitle ............... [action]` — so a screen
/// never hand-builds that row and no two cards head themselves differently.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.selected = false,
    required this.child,
  });

  final Widget? title;

  /// The muted one-liner under the title ("Completed sales today").
  final Widget? subtitle;

  /// Usually an [AppIconChip] — the pale square an icon sits in.
  final Widget? leading;

  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;

  /// When set, the whole card becomes a single tap target (e.g. a
  /// clickable stat card), with hover/pressed feedback from `InkWell`.
  final VoidCallback? onTap;

  /// Draws the card with the accent border/fill used for a chosen item —
  /// e.g. the active entry in a settings list.
  final bool selected;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasHeader = title != null || subtitle != null || leading != null || actions != null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasHeader) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.md)],
              if (title != null || subtitle != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        DefaultTextStyle.merge(
                          style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
                          child: title!,
                        ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: DefaultTextStyle.merge(
                            style: AppTypography.cardSubtitle.copyWith(color: colors.textMuted),
                            child: subtitle!,
                          ),
                        ),
                    ],
                  ),
                ),
              ...?actions,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        child,
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.card,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: selected ? colors.primary : colors.border),
        boxShadow: context.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.cardRadius,
        // A real Material ancestor, not just the decoration above —
        // content that includes a ListTile (several modules' cards do)
        // paints its background/ink splashes on the nearest Material
        // ancestor; without one, Flutter raises a real "may be invisible"
        // assertion. `transparency` so this never overrides the card
        // color set above.
        child: Material(
          type: MaterialType.transparency,
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  hoverColor: colors.primary.withValues(alpha: 0.04),
                  child: Padding(padding: padding, child: content),
                )
              : Padding(padding: padding, child: content),
        ),
      ),
    );
  }
}

/// A panel nested *inside* an [AppCard] — the grey well behind a sub-list
/// or a summary block. Flat and unbordered on purpose: a second bordered,
/// shadowed card inside a card is what makes dense screens look like boxes
/// in boxes (§33).
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceMuted,
      borderRadius: AppRadius.lgRadius,
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(onTap: onTap, child: Padding(padding: padding, child: child))
          : Padding(padding: padding, child: child),
    );
  }
}
