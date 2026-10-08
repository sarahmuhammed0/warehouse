import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/file_download.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../data/audit_models.dart';
import '../data/audit_providers.dart';

/// One entry from §30's trail, opened from the list.
///
/// The table shows four columns because a table has to fit; the record has
/// more — who the actor was, which record was touched, the address it came
/// from. Those are the fields that make an entry checkable against anything
/// else, so they belong somewhere, and a dialog over the list is cheaper to
/// open and close than a screen you have to navigate back from.
Future<void> showActivityEntryDialog(BuildContext context, AuditLogEntry entry) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ActivityEntryDialog(entry: entry),
  );
}

class _ActivityEntryDialog extends ConsumerStatefulWidget {
  const _ActivityEntryDialog({required this.entry});

  final AuditLogEntry entry;

  @override
  ConsumerState<_ActivityEntryDialog> createState() => _ActivityEntryDialogState();
}

class _ActivityEntryDialogState extends ConsumerState<_ActivityEntryDialog> {
  bool _saving = false;

  /// Fetches the document and hands it over.
  ///
  /// Rendered by the SERVER from the row as recorded — the trail is evidence,
  /// and a copy drawn from what this screen happens to be showing would be a
  /// different kind of thing. Every failure says what happened rather than
  /// leaving a button that does nothing.
  Future<void> _saveAsPdf() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      final bytes = await ref.read(auditRepositoryProvider).entryPdf(widget.entry.id);
      if (bytes.isEmpty) {
        if (mounted) AppToast.error(context, l10n.unableToLoad);
        return;
      }
      final filename = 'activity-${widget.entry.id}.pdf';
      await downloadBytes(bytes: bytes, filename: filename, mimeType: 'application/pdf');
      if (mounted) AppToast.success(context, l10n.pdfSaved(filename));
    } on Failure catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (mounted) AppToast.error(context, l10n.unableToLoad);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final entry = widget.entry;

    final rows = <(String, String)>[
      (l10n.fieldEmployee, entry.userName),
      (l10n.fieldModule, _humanise(entry.module)),
      (l10n.fieldAction, _actionLabel(entry.action)),
      (l10n.fieldDate, _formatDateTime(entry.createdAt)),
      if (entry.referenceId != null) (l10n.fieldReference, '#${entry.referenceId}'),
      (l10n.fieldIpAddress, entry.ipAddress ?? '—'),
    ];

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
      title: Text(l10n.activityEntryTitle, style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What happened, in the words the trail recorded at the time —
            // never re-derived from today's data.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: AppRadius.mdRadius),
              child: Text(entry.description, style: AppTypography.body.copyWith(color: colors.textPrimary)),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ),
                    Expanded(
                      child: Text(value, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l10n.close,
          variant: AppButtonVariant.text,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('activitySavePdf'),
          label: l10n.saveAsPdf,
          icon: Icons.picture_as_pdf_outlined,
          loading: _saving,
          onPressed: _saving ? null : _saveAsPdf,
        ),
      ],
    );
  }
}

/// The action without the module it already sits beside.
///
/// The trail stores `auth.login_success`, and Module is the row above — so the
/// raw value reads "Auth.login success" under a row already saying "Auth". Same
/// rule as the printed document, so the screen and the file agree.
String _actionLabel(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '—';
  final withoutModule = raw.contains('.') ? raw.substring(raw.indexOf('.') + 1) : raw;
  return _humanise(withoutModule);
}

String _humanise(String value) {
  final text = value.replaceAll('_', ' ').trim();
  if (text.isEmpty) return '—';
  return text[0].toUpperCase() + text.substring(1);
}

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
