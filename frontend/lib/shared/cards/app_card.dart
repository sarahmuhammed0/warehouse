import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Base bordered-container primitive (architecture §27/§16) — every other
/// card in the shared library (`shared/dashboard/*`) composes this one
/// instead of redefining border/radius/padding. Flat + hairline border by
/// design (§2: no decorative shadow stacking).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.actions,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    required this.child,
  });

  final Widget? title;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;

  /// When set, the whole card becomes a single tap target (e.g. a
  /// clickable stat card) — hover/pressed/ripple feedback and the pointer
  /// cursor all come from `InkWell`'s own Material defaults, kept
  /// deliberately plain (no custom colors) to match this app's flat,
  /// non-flashy design language.
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || actions != null) ...[
          Row(
            children: [
              if (title != null)
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
                    child: title!,
                  ),
                ),
              ...?actions,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        child,
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: AppRadius.mdRadius,
      ),
      // A real Material ancestor, not just this Container's own
      // BoxDecoration — content that includes a ListTile (several modules'
      // cards do) paints its background/ink splashes on the nearest
      // Material ancestor; without one, Flutter raises a real "may be
      // invisible" assertion. `transparency` so this never overrides the
      // Container's own background color above.
      child: Material(
        type: MaterialType.transparency,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: AppRadius.mdRadius,
                child: Padding(padding: padding, child: content),
              )
            : Padding(padding: padding, child: content),
      ),
    );
  }
}
