import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../../../theme/app_typography.dart';

/// Builds the CSV a report would export, and shows it.
///
/// §48 wants reports exportable; real file generation is backend work (the
/// spec's own §38 lists no export endpoint, and nothing here can write a
/// file to disk on web). What this frontend *can* do honestly is produce
/// the exact content and hand it over — so the Export button that used to
/// be `onPressed: () {}` now shows the real rows and copies them to the
/// clipboard, and says plainly that server-side generation comes later.
String buildCsv(List<String> headers, List<List<String>> rows) {
  String escape(String value) {
    final needsQuotes = value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  return [
    headers.map(escape).join(','),
    for (final row in rows) row.map(escape).join(','),
  ].join('\n');
}

Future<void> showExportPreview(
  BuildContext context, {
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final csv = buildCsv(headers, rows);
  return showAppDialog<void>(
    context,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text('${l10n.exportPreviewTitle} — $title'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(l10n.totalRecords(rows.length), style: AppTypography.bodyStrong),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: SelectableText(csv, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.exportPreviewNotice, style: AppTypography.caption)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          AppButton(label: l10n.close, variant: AppButtonVariant.text, onPressed: () => Navigator.of(context).pop()),
          AppButton(
            label: l10n.copy,
            icon: Icons.copy_all_outlined,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              AppToast.success(context, l10n.copiedToClipboard);
            },
          ),
        ],
      );
    },
  );
}
