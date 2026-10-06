import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';
import '../../l10n/generated/app_localizations.dart';
import '../overlays/app_dialog.dart';
import 'form_field_wrapper.dart';

/// The "you have to choose something" message, translated.
///
/// Nullable `of` with a literal fallback rather than `of(context)!`: these are
/// the lowest-level widgets in the app and are built in tests that do not always
/// install the localisation delegates. A field that cannot find them should
/// still refuse an empty value — in English — rather than throw.
String _requiredMessage(BuildContext context) =>
    AppLocalizations.of(context)?.requiredFieldMessage ?? 'This field is required.';

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

  /// The caller's own rule first, then the generic one — the same order as
  /// [AppTextField], and for the same reason: a field that already has a message
  /// of its own keeps it, and the generic check is only a floor for the fields
  /// that had none.
  FormFieldValidator<T?>? _validator(BuildContext context) {
    if (!required) return validator;
    final message = _requiredMessage(context);
    final caller = validator;
    return (value) => caller?.call(value) ?? (value == null ? message : null);
  }

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: label,
      required: required,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        // Without this, a long option label (a real category/role/status
        // name, not just short test fixtures) overflows the dropdown's
        // internal Row instead of truncating — a real rendering bug this
        // phase's tests caught live, not a hypothetical.
        isExpanded: true,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.label, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
        // Marking a dropdown required now actually refuses an empty one.
        // `required` used to reach [FormFieldWrapper] for the asterisk and stop
        // there, and `validator` takes a `FormFieldValidator<T?>` that in
        // practice no caller passed — so every required dropdown in the app
        // accepted "nothing selected" and submitted it.
        validator: _validator(context),
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
            // A required type-to-filter select had no check at all: the
            // asterisk was drawn and the inner field validated nothing, so an
            // order could be submitted with no customer picked.
            //
            // "Has a value" here means the text matches one of the options,
            // not merely that something was typed. `onSelected` is the only
            // way a value reaches the form, so a half-typed "Ahm" that was
            // never picked from the list IS nothing chosen — and submitting it
            // would drop the choice silently, which is the failure this is
            // meant to prevent. An edit form's `initialValue` is an option
            // label, so it still passes.
            validator: !required
                ? null
                : (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return _requiredMessage(context);
                    final matches = options.any((o) => o.label == text);
                    return matches ? null : _requiredMessage(context);
                  },
            autovalidateMode: AutovalidateMode.onUserInteraction,
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
      // A real [FormField] rather than a bare [InputDecorator], so that
      // `Form.validate()` can reach this field at all. An `InputDecorator` is
      // only the chrome — it is not part of the form, gets no `errorText`, and
      // therefore could never turn red however empty it was.
      //
      // `initialValue: selected` plus `didChange` in the picker keeps the
      // field's own value in step with the parent's, so the error clears the
      // moment something is ticked instead of waiting for the next submit.
      child: FormField<Set<T>>(
        initialValue: selected,
        validator: !required ? null : (value) => (value == null || value.isEmpty) ? _requiredMessage(context) : null,
        builder: (state) => InkWell(
          borderRadius: AppRadius.mdRadius,
          onTap: () => _openPicker(context, state),
          child: InputDecorator(
            // `applyDefaults` is not optional here. `TextField` merges
            // `InputDecorationTheme` into its decoration for you; a bare
            // `InputDecorator` does not, so without this the field reported its
            // error and then drew it with Material's own default underline
            // instead of the app's red `errorBorder` — the message appeared and
            // the border stayed the normal colour, which is the half of "show me
            // which field" that people actually see.
            decoration: InputDecoration(
              errorText: state.errorText,
            ).applyDefaults(Theme.of(context).inputDecorationTheme),
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
                          onDeleted: () {
                            final next = Set.of(selected)..remove(option.value);
                            state.didChange(next);
                            onChanged(next);
                          },
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, FormFieldState<Set<T>> state) async {
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
                state.didChange(working);
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
