import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Reusable confirmation dialog for every future destructive/sensitive
/// action (§15/§17: delete, cancel order, return, approve, reject, status
/// changes). One shape, one call site pattern — `confirmAction(...)`
/// returns `true`/`false`/`null` (dismissed), so callers write:
/// ```dart
/// if (await confirmAction(context, title: 'Cancel order?', ...) ?? false) {
///   // proceed — not implemented until the module that owns this action
/// }
/// ```
/// [isDestructive] switches the confirm button to the destructive variant
/// — the visual cue that this isn't a routine "OK".
Future<bool?> confirmAction(
  BuildContext context, {
  required String title,
  String description = 'This action cannot be undone.',
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => ConfirmDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
    ),
  );
}

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDestructive,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      // A destructive confirmation gets a tinted icon well above the
      // question (§17's "destructive confirmation styling") — the colour
      // arrives before the sentence is read, which is the point of asking.
      icon: isDestructive
          ? Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.lgRadius),
              child: Icon(Icons.warning_amber_rounded, size: 24, color: colors.error),
            )
          : null,
      iconPadding: const EdgeInsets.only(top: AppSpacing.xl),
      title: Text(title, style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary)),
      titlePadding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        isDestructive ? AppSpacing.lg : AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      content: Text(description, style: AppTypography.body.copyWith(color: colors.textSecondary)),
      contentPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: isDestructive ? AppButtonVariant.destructive : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
