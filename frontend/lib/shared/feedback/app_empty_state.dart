import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Empty state (§15/§41) — icon + title + description + an optional
/// action, used both for "no data exists yet" and "no results match your
/// filters" (the caller supplies different copy for each; this widget
/// doesn't guess which one it is).
///
/// The icon sits in a soft round well rather than floating on the surface,
/// which is the same treatment every icon in this design system gets — it
/// stops an empty table from looking like a rendering failure.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: AppRadius.lgRadius,
            ),
            child: Icon(icon, size: 26, color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: actionLabel!, onPressed: onAction, variant: AppButtonVariant.secondary),
          ],
        ],
      ),
    );
  }
}
