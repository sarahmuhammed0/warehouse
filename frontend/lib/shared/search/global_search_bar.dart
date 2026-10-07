import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// Global search (§17/§32) — lives in the top bar, visible on every screen.
///
/// A borderless pill on a muted fill rather than an outlined field: it sits
/// in the header chrome next to circular icon buttons, and an outlined
/// input there reads as a form control dropped into the navigation.
class GlobalSearchBar extends StatelessWidget {
  const GlobalSearchBar({super.key, this.onSubmitted, this.controller, this.autofocus = false});

  final ValueChanged<String>? onSubmitted;

  /// Supplied by the results screen, which opens holding the current query so
  /// it can be read and refined rather than retyped.
  final TextEditingController? controller;

  /// True on the results screen: arriving there means the intent is to type.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        style: AppTypography.body.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.searchPlaceholder,
          prefixIcon: Icon(Icons.search, size: 19, color: colors.textMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: colors.surfaceMuted,
          border: const OutlineInputBorder(
            borderRadius: AppRadius.pillRadius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: AppRadius.pillRadius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.pillRadius,
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
