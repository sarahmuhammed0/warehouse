import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// Global search (§17/§32) — lives in the top bar, visible on every screen.
/// No backend to query yet (Phase 1 has no products/orders/customers), so
/// `onSubmitted` is currently unused by any caller; the field itself is
/// real and functional, just not wired to a query yet.
class GlobalSearchBar extends StatelessWidget {
  const GlobalSearchBar({super.key, this.onSubmitted});

  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      height: 38,
      child: TextField(
        onSubmitted: onSubmitted,
        style: AppTypography.body.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.searchPlaceholder,
          prefixIcon: Icon(Icons.search, size: 19, color: colors.textMuted),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mdRadius,
            borderSide: BorderSide(color: colors.border),
          ),
          filled: true,
          fillColor: colors.background,
        ),
      ),
    );
  }
}
