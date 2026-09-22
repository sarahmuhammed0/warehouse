import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Error state (§15/§31/§41) — icon + message + retry. The message is
/// always something the caller already turned into plain language (e.g. a
/// `Failure.message` from `core/error/failure.dart`) — this widget never
/// receives or renders a raw exception itself.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

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
              color: colors.errorBg,
              borderRadius: AppRadius.lgRadius,
            ),
            child: Icon(Icons.error_outline, size: 26, color: colors.error),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: colors.textMuted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry, variant: AppButtonVariant.outline),
          ],
        ],
      ),
    );
  }
}
