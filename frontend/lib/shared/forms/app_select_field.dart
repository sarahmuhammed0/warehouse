import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';
import '../overlays/app_dialog.dart';
import 'form_field_wrapper.dart';

class AppSelectOption<T> {
  const AppSelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// Plain dropdown/select (§12). Built on Flutter's own
/// `DropdownButtonFormField` — no reason to reimplement it.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.helperText,
    this.validator,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final bool required;
  final String? helperText;
  final FormFieldValidator<T?>? validator;

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: label,
      required: required,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.label)),
        ],
        onChanged: onChanged,
        validator: validator,
        decoration: InputDecoration(helperText: helperText),
      ),
    );
  }
}

/// Type-to-filter select (§12) — built on Flutter's `Autocomplete`, which
/// already handles the filtering/overlay/keyboard-navigation mechanics;
/// this wraps it with the app's field chrome and label.
class AppSearchableSelectField<T extends Object> extends StatelessWidget {
  const AppSearchableSelectField({
    super.key,
    required this.label,
    required this.options,
    this.initialValue,
    required this.onSelected,
    this.required = false,
    this.hintText,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final AppSelectOption<T>? initialValue;
  final ValueChanged<T> onSelected;
  final bool required;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: label,
      required: required,
      child: Autocomplete<AppSelectOption<T>>(
        initialValue: TextEditingValue(text: initialValue?.label ?? ''),
        displayStringForOption: (option) => option.label,
        optionsBuilder: (query) {
          if (query.text.isEmpty) return options;
          final q = query.text.toLowerCase();
          return options.where((o) => o.label.toLowerCase().contains(q));
        },
        onSelected: (option) => onSelected(option.value),
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(hintText: hintText ?? 'Search…'),
          );
        },
        optionsViewBuilder: (context, onSelected, results) {
          final colors = context.colors;
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 2,
              borderRadius: AppRadius.mdRadius,
              color: colors.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240, minWidth: 240),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final option in results)
                      ListTile(
                        dense: true,
                        title: Text(option.label, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                        onTap: () => onSelected(option),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Multi-select (§12) — selected values render as removable chips inline;
/// tapping opens a checkbox list in a dialog to change the selection.
class AppMultiSelectField<T> extends StatelessWidget {
  const AppMultiSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedOptions = options.where((o) => selected.contains(o.value)).toList();

    return FormFieldWrapper(
      label: label,
      required: required,
      child: InkWell(
        borderRadius: AppRadius.mdRadius,
        onTap: () => _openPicker(context),
        child: InputDecorator(
          decoration: const InputDecoration(),
          child: selectedOptions.isEmpty
              ? Text('Select…', style: AppTypography.body.copyWith(color: colors.textMuted))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in selectedOptions)
                      Chip(
                        label: Text(option.label),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => onChanged(Set.of(selected)..remove(option.value)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    var working = Set<T>.from(selected);
    await showAppDialog<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  CheckboxListTile(
                    value: working.contains(option.value),
                    title: Text(option.label),
                    onChanged: (checked) => setState(() {
                      checked ?? false ? working.add(option.value) : working.remove(option.value);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            AppButton(
              label: 'Apply',
              onPressed: () {
                onChanged(working);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
