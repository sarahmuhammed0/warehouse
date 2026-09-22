import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Server-side pagination controls (§18/§26) — this widget only ever
/// renders a bounded page of rows a repository already fetched; it never
/// implies "load everything," which is the whole point of the requirement.
/// `page` is 1-based. Callers pass an already-computed `totalPages`; this
/// widget does no math on `totalItems` itself so it stays agnostic to
/// whatever pagination shape a future API responds with.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.pageSize,
    required this.pageSizeOptions,
    this.onPageChanged,
    this.onPageSizeChanged,
    this.loading = false,
  });

  final int page;
  final int totalPages;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final bool loading;

  bool get _canGoBack => !loading && page > 1 && onPageChanged != null;
  bool get _canGoForward => !loading && page < totalPages && onPageChanged != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    // "Next"/"previous" are reading-direction concepts, not literal
    // left/right (§21) — chevron_left/right/first_page/last_page are literal
    // glyphs Flutter does not auto-mirror, so they're picked explicitly here.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final firstIcon = isRtl ? Icons.last_page : Icons.first_page;
    final lastIcon = isRtl ? Icons.first_page : Icons.last_page;
    final previousIcon = isRtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        if (onPageSizeChanged != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.rowsPerPage, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.pillRadius,
                ),
                child: DropdownButton<int>(
                  value: pageSize,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  borderRadius: AppRadius.mdRadius,
                  style: AppTypography.label.copyWith(color: colors.textPrimary),
                  items: [
                    for (final size in pageSizeOptions) DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: loading ? null : (value) => value == null ? null : onPageSizeChanged!(value),
                ),
              ),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PageButton(
              icon: firstIcon,
              tooltip: l10n.firstPage,
              onTap: _canGoBack ? () => onPageChanged!(1) : null,
            ),
            _PageButton(
              icon: previousIcon,
              tooltip: l10n.previousPage,
              onTap: _canGoBack ? () => onPageChanged!(page - 1) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                l10n.pageOfTotal(page, totalPages < 1 ? 1 : totalPages),
                style: AppTypography.label.copyWith(color: colors.textPrimary),
              ),
            ),
            _PageButton(
              icon: nextIcon,
              tooltip: l10n.nextPage,
              onTap: _canGoForward ? () => onPageChanged!(page + 1) : null,
            ),
            _PageButton(
              icon: lastIcon,
              tooltip: l10n.lastPage,
              onTap: _canGoForward ? () => onPageChanged!(totalPages) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(icon: icon, tooltip: tooltip, onPressed: onTap);
  }
}
