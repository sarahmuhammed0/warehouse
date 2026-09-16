import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
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
      title: Text(title, style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary)),
      content: Text(description, style: AppTypography.body.copyWith(color: colors.textSecondary)),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.text,
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
