import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The date-range control beside a dashboard's title.
///
/// It is a real control, not a date stamp wearing a button's clothes: the
/// period it names is the period the dashboard's overview chart plots, and
/// choosing another one re-plots it. A pill with a border and a chevron
/// that did nothing would be exactly the dead control §57 rules out — if
/// there were no range to change, this widget would not exist and the date
/// would be plain text.
///
/// Generic over the period type so each dashboard offers the ranges its own
/// data actually covers: days/weeks/months on the business side, months on
/// the platform side.
class DateRangeChip<T> extends StatelessWidget {
  const DateRangeChip({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.span,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// The concrete dates the current range covers, e.g. "4/26 — 9/26".
  /// Shown after the range's name so the control says both what was chosen
  /// and what that means.
  final String? span;

  /// There is only room for the dates alongside the range's name once the
  /// window is past phone width.
  static bool showSpan(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = options.firstWhere(
      (o) => o.value == selected,
      orElse: () => options.first,
    );

    return PopupMenuButton<T>(
      tooltip: current.label,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      // Wide enough for a spelled-out range name ("Monthly sales (last 6
      // months)"); Material's default menu width is narrower than that and
      // the row inside would overflow rather than wrap.
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 340),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            child: Row(
              children: [
                Icon(
                  option.value == selected ? Icons.check : Icons.calendar_today_outlined,
                  size: 17,
                  color: option.value == selected ? colors.primary : colors.textMuted,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    option.label,
                    style: AppTypography.body.copyWith(
                      color: colors.textPrimary,
                      fontWeight: option.value == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg, end: AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(color: colors.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            // Flexible, not a bare Text: a range name plus the dates it
            // covers is long, and on a phone this chip sits in a `Wrap`
            // that hands it the full line — without this it overflows
            // rather than truncating.
            Flexible(
              child: Text(
                // The dates are supporting detail; below tablet width the
                // chip keeps the name and drops them rather than eliding
                // both into nothing.
                span == null || !showSpan(context) ? current.label : '${current.label} · $span',
                style: AppTypography.button.copyWith(color: colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
