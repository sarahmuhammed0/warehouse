import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'form_field_wrapper.dart';

/// Same fallback as the select fields: these are built in tests that do not
/// always install the localisation delegates, and a date field that cannot find
/// them should still refuse an empty value rather than throw.
String _requiredMessage(BuildContext context) =>
    AppLocalizations.of(context)?.requiredFieldMessage ?? 'This field is required.';

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Single date picker (§12), built on Flutter's `showDatePicker`. Display
/// format is a plain ISO date for now — locale-aware date formatting
/// (architecture's per-business `date_format` setting) is wired once
/// Settings exists.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FormFieldWrapper(
      label: label,
      required: required,
      // A [FormField], not a bare [InputDecorator] — see the note in
      // AppMultiSelectField: an InputDecorator is chrome only, never part of
      // the form, so a required date could never be reported as missing.
      child: FormField<DateTime>(
        initialValue: value,
        validator: !required ? null : (date) => date == null ? _requiredMessage(context) : null,
        builder: (state) => InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: firstDate ?? DateTime(2000),
              lastDate: lastDate ?? DateTime(2100),
            );
            if (picked != null) {
              state.didChange(picked);
              onChanged(picked);
            }
          },
          child: InputDecorator(
            // `applyDefaults` so the app's red `errorBorder` reaches this field:
            // `TextField` merges `InputDecorationTheme` for you, a bare
            // `InputDecorator` does not. Without it the date reported its error
            // and drew it in Material's default colours, so the message showed
            // and the border did not go red.
            decoration: InputDecoration(
              errorText: state.errorText,
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: colors.textMuted),
            ).applyDefaults(Theme.of(context).inputDecorationTheme),
            child: Text(
              value != null ? _formatDate(value!) : 'Select date',
              style: TextStyle(color: value != null ? colors.textPrimary : colors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Date-range picker (§25/§26's report/filter date ranges), built on
/// Flutter's `showDateRangePicker`.
class AppDateRangeField extends StatelessWidget {
  const AppDateRangeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final bool required;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FormFieldWrapper(
      label: label,
      required: required,
      child: FormField<DateTimeRange>(
        initialValue: value,
        validator: !required ? null : (range) => range == null ? _requiredMessage(context) : null,
        builder: (state) => InkWell(
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              initialDateRange: value,
              firstDate: firstDate ?? DateTime(2000),
              lastDate: lastDate ?? DateTime(2100),
            );
            if (picked != null) {
              state.didChange(picked);
              onChanged(picked);
            }
          },
          child: InputDecorator(
            // Same reason as [AppDateField] above.
            decoration: InputDecoration(
              errorText: state.errorText,
              suffixIcon: Icon(Icons.date_range_outlined, size: 18, color: colors.textMuted),
            ).applyDefaults(Theme.of(context).inputDecorationTheme),
            child: Text(
              value != null ? '${_formatDate(value!.start)} — ${_formatDate(value!.end)}' : 'Select date range',
              style: TextStyle(color: value != null ? colors.textPrimary : colors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
