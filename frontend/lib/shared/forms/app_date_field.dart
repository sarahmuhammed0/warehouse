import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'form_field_wrapper.dart';

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
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2000),
            lastDate: lastDate ?? DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: colors.textMuted)),
          child: Text(
            value != null ? _formatDate(value!) : 'Select date',
            style: TextStyle(color: value != null ? colors.textPrimary : colors.textMuted),
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
      child: InkWell(
        onTap: () async {
          final picked = await showDateRangePicker(
            context: context,
            initialDateRange: value,
            firstDate: firstDate ?? DateTime(2000),
            lastDate: lastDate ?? DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(suffixIcon: Icon(Icons.date_range_outlined, size: 18, color: colors.textMuted)),
          child: Text(
            value != null ? '${_formatDate(value!.start)} — ${_formatDate(value!.end)}' : 'Select date range',
            style: TextStyle(color: value != null ? colors.textPrimary : colors.textMuted),
          ),
        ),
      ),
    );
  }
}
