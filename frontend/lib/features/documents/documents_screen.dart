import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/feedback/app_empty_state.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../orders/data/order_providers.dart';
import '../settings/data/settings_state.dart';

/// Documents (spec §25/§27) — the sales-document PDF preview. Real server
/// PDF generation is explicitly deferred (§25's own instruction); this
/// screen renders the same fields the eventual PDF would contain, sourced
/// from the most recent real order and the Settings → PDF template toggles,
/// so the preview genuinely reflects what's configured rather than being a
/// static mockup image.
class DocumentsPlaceholderScreen extends ConsumerWidget {
  const DocumentsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final orders = ref.watch(orderListControllerProvider).items;
    final settings = ref.watch(businessSettingsProvider);
    final sample = orders.isEmpty ? null : orders.first;

    return PageScaffold(
      title: l10n.navDocuments,
      secondaryActions: [
        AppButton(label: l10n.pdfTemplateBuilderLabel, icon: Icons.tune, variant: AppButtonVariant.outline, onPressed: () => context.go(AppRoutes.settings)),
      ],
      body: sample == null
          ? AppEmptyState(icon: Icons.description_outlined, title: l10n.emptyStateDefaultTitle, description: l10n.demoDataNotice)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      if (settings.pdfShowLogo)
                        Container(width: 48, height: 48, color: colors.selectedBg, alignment: Alignment.center, child: const Icon(Icons.image_outlined)),
                      Text(settings.businessName, style: AppTypography.pageTitle),
                      const Divider(),
                      Text('${l10n.fieldOrderNumber}: ${sample.orderNumber}'),
                      Text('${l10n.fieldDate}: ${sample.createdAt.toString().split(' ').first}'),
                      Text('${l10n.fieldCustomer}: ${sample.customerName ?? '—'}'),
                      const Divider(),
                      for (final item in sample.items)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [Text('${item.productName} ×${item.quantity}'), Text(item.lineTotal.toStringAsFixed(2))],
                        ),
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l10n.fieldGrandTotal, style: AppTypography.bodyStrong), Text(sample.grandTotal.toStringAsFixed(2), style: AppTypography.bodyStrong)]),
                      if (settings.pdfShowTaxInfo) Text('${l10n.fieldTax}: ${sample.taxTotal.toStringAsFixed(2)}', style: AppTypography.caption),
                      const Divider(),
                      Text(settings.pdfFooterText, style: AppTypography.caption),
                      if (settings.pdfShowSignature) Text('_________________ ${l10n.fieldEmployee}', style: AppTypography.caption),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
