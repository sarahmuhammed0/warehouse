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
  final _focus = FocusNode();

  /// Seeding once is right while the user is typing, and wrong when the value
  /// arrives after the first build — which is exactly what happens in backend
  /// mode, where Settings are fetched and the first frame shows defaults. A
  /// field seeded once would keep showing "USD" after the server said "IQD".
  ///
  /// So it re-seeds when the incoming value changes AND the field is not
  /// focused. The focus check is what keeps the original fix intact: the box
  /// someone is actively typing in is never written over.
  @override
  void didUpdateWidget(SettingsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text &&
        !_focus.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `Focus` draws nothing — it is here only so [didUpdateWidget] can ask
    // whether this field is the one being typed in. `AppTextField` is a shared
    // design component and takes no focus node; wrapping keeps the question
    // answerable without changing it or how anything looks.
    return Focus(
      focusNode: _focus,
      canRequestFocus: false,
      child: _field(),
    );
  }

  Widget _field() {
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
