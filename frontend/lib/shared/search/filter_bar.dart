import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// One active filter, shown as a removable chip — e.g. "Category: Sofas",
/// "Date: Last 30 days" (§17/§25's date range / product / category / user /
/// location filters). The filter *definitions* and the panel that edits
/// them are entirely up to the feature that owns them (opened via
/// `shared/overlays/app_overlay_panel.dart`); this widget only renders
/// whatever is currently active.
class FilterChipData {
  const FilterChipData({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
}

/// A "Filters" button (opens the feature's own filter panel) plus the
/// active-filter chips row and a "Clear filters" action once any are set.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    super.key,
    required this.activeFilters,
    required this.onOpenFilters,
    this.onClearAll,
  });

  final List<FilterChipData> activeFilters;
  final VoidCallback onOpenFilters;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(
          label: activeFilters.isEmpty ? l10n.filters : '${l10n.filters} (${activeFilters.length})',
          icon: Icons.filter_list,
          variant: AppButtonVariant.outline,
          size: AppButtonSize.small,
          onPressed: onOpenFilters,
        ),
        for (final filter in activeFilters)
          Container(
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.xs),
            height: 36,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: AppRadius.pillRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filter.label,
                  style: AppTypography.label.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: filter.onRemove,
                  borderRadius: AppRadius.pillRadius,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.close, size: 14, color: colors.primary),
                  ),
                ),
              ],
            ),
          ),
        if (activeFilters.isNotEmpty && onClearAll != null)
          AppButton(
            label: l10n.clearFilters,
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            onPressed: onClearAll,
          ),
      ],
    );
  }
}
