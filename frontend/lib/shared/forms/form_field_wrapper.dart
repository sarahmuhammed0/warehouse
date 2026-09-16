import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The shared label chrome every field in this file uses (§12) — a
/// consistent label + required-asterisk treatment above the input, so no
/// two form fields in the app label themselves differently. Helper text and
/// validation errors are intentionally NOT duplicated here — they're
/// rendered by the underlying Flutter field's own `InputDecoration`
/// (already styled once, globally, in `theme/app_theme.dart`), so there is
/// exactly one place error-message styling is defined.
class FormFieldWrapper extends StatelessWidget {
  const FormFieldWrapper({super.key, required this.label, this.required = false, required this.child});

  final String label;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: RichText(
            text: TextSpan(
              style: AppTypography.formLabel.copyWith(color: colors.textSecondary),
              children: [
                TextSpan(text: label),
                if (required) TextSpan(text: ' *', style: TextStyle(color: colors.error)),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
