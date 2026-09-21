import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Checkbox with an inline label (§12) — a single tappable row rather than
/// a bare `Checkbox`, so every checkbox in the app has the same touch
/// target size and label treatment.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: AppTypography.body.copyWith(color: context.colors.textPrimary)),
      subtitle: helperText != null
          ? Text(helperText!, style: AppTypography.helperText.copyWith(color: context.colors.textMuted))
          : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class AppRadioOption<T> {
  const AppRadioOption(this.value, this.label);
  final T value;
  final String label;
}

/// Radio group (§12) — one required group label plus its options, so a
/// screen never has to hand-build the group label separately from the
/// individual `Radio` widgets.
class AppRadioGroup<T> extends StatelessWidget {
  const AppRadioGroup({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<AppRadioOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label, style: AppTypography.formLabel.copyWith(color: colors.textSecondary)),
        ),
        RadioGroup<T>(
          groupValue: value,
          onChanged: onChanged,
          child: Column(
            children: [
              for (final option in options)
                RadioListTile<T>(
                  value: option.value,
                  title: Text(option.label, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Toggle switch with an inline label (§12).
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.label, required this.value, required this.onChanged, this.helperText});

  final String label;
  final bool value;

  /// Nullable so a caller can genuinely disable it. It used to be
  /// non-nullable, so every form that wanted to lock the switch while
  /// saving passed `(_) {}` — which leaves `Switch` looking fully
  /// interactive while silently swallowing taps. `null` greys it out, the
  /// same way the buttons beside it already behaved.
  final ValueChanged<bool>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.body.copyWith(color: colors.textPrimary)),
              if (helperText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(helperText!, style: AppTypography.helperText.copyWith(color: colors.textMuted)),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
