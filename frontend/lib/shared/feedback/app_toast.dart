import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../badges/status_badge.dart';

/// The one notification mechanism every future module uses after a
/// create/update/delete/status-change action (§15) — `AppToast.success(context,
/// 'Order ORD-2026-000042 created')`, never a bare `ScaffoldMessenger` call
/// built ad hoc per screen. Built on [SnackBar] (auto-adapts position/width
/// reasonably across breakpoints without extra work here).
class AppToast {
  AppToast._();

  static void success(BuildContext context, String message) => _show(context, message, StatusTone.success, Icons.check_circle_outline);
  static void error(BuildContext context, String message) => _show(context, message, StatusTone.danger, Icons.error_outline);
  static void warning(BuildContext context, String message) => _show(context, message, StatusTone.warning, Icons.warning_amber_outlined);
  static void info(BuildContext context, String message) => _show(context, message, StatusTone.info, Icons.info_outline);

  static void _show(BuildContext context, String message, StatusTone tone, IconData icon) {
    final colors = context.colors;
    final accent = switch (tone) {
      StatusTone.success => colors.success,
      StatusTone.warning => colors.warning,
      StatusTone.danger => colors.error,
      StatusTone.info => colors.info,
      StatusTone.neutral => colors.textSecondary,
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message, style: AppTypography.body.copyWith(color: colors.surface))),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdRadius,
            side: BorderSide(color: accent.withValues(alpha: 0.5)),
          ),
          width: MediaQuery.sizeOf(context).width < 600 ? null : 420,
        ),
      );
  }
}
