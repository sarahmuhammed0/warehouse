import 'package:flutter/material.dart';

import '../../../shared/forms/app_text_field.dart';

/// A Settings text field that owns its own `TextEditingController`.
///
/// Every settings input used to build `TextEditingController(text: ...)`
/// inline in `build()`. `BusinessSettingsData` has no `==`, so each
/// keystroke produced a new state object, rebuilt the section, and handed
/// the field a **brand-new controller** seeded from the provider — which
/// reset the selection to offset -1 and bounced the caret out of position
/// on every character. The number fields were worse: clearing the box
/// failed to parse, so the old value was immediately re-rendered and you
/// could not delete a digit. None of the controllers were ever disposed
/// either, so one leaked per keystroke.
///
/// Seeding once and writing through fixes all of it. The provider stays the
/// source of truth; this widget just stops re-seeding the field the user is
/// actively typing in.
class SettingsField extends StatefulWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.number = false,
    this.maxLines,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool number;
  final int? maxLines;

  @override
  State<SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<SettingsField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.number) {
      return AppTextField.number(
        label: widget.label,
        controller: _controller,
        allowDecimal: false,
        onChanged: widget.onChanged,
      );
    }
    if (widget.maxLines != null) {
      return AppTextField.multiline(
        label: widget.label,
        controller: _controller,
        maxLines: widget.maxLines!,
        onChanged: widget.onChanged,
      );
    }
    return AppTextField(label: widget.label, controller: _controller, onChanged: widget.onChanged);
  }
}
