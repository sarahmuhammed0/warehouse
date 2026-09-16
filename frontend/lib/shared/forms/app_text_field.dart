import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'form_field_wrapper.dart';

/// One field, four shapes (§12: text/password/number/text-area) — a
/// dedicated file per input type would just be four copies of the same
/// label/validation/disabled wiring with a different `keyboardType`.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.required = false,
    this.hintText,
    this.helperText,
    this.validator,
    this.enabled = true,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
  }) : _obscure = false,
       _numbersOnly = false;

  const AppTextField.password({
    super.key,
    required this.label,
    this.controller,
    this.required = false,
    this.hintText,
    this.helperText,
    this.validator,
    this.enabled = true,
    this.onChanged,
  }) : keyboardType = TextInputType.visiblePassword,
       maxLines = 1,
       _obscure = true,
       _numbersOnly = false;

  const AppTextField.number({
    super.key,
    required this.label,
    this.controller,
    this.required = false,
    this.hintText,
    this.helperText,
    this.validator,
    this.enabled = true,
    this.onChanged,
    bool allowDecimal = true,
  }) : keyboardType = allowDecimal
           ? const TextInputType.numberWithOptions(decimal: true)
           : TextInputType.number,
       maxLines = 1,
       _obscure = false,
       _numbersOnly = true;

  const AppTextField.multiline({
    super.key,
    required this.label,
    this.controller,
    this.required = false,
    this.hintText,
    this.helperText,
    this.validator,
    this.enabled = true,
    this.onChanged,
    this.maxLines = 4,
  }) : keyboardType = TextInputType.multiline,
       _obscure = false,
       _numbersOnly = false;

  final String label;
  final TextEditingController? controller;
  final bool required;
  final String? hintText;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool _obscure;
  final bool _numbersOnly;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return FormFieldWrapper(
      label: widget.label,
      required: widget.required,
      child: TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: widget._obscure && _obscured,
        keyboardType: widget.keyboardType,
        maxLines: widget._obscure ? 1 : widget.maxLines,
        onChanged: widget.onChanged,
        validator: widget.validator,
        inputFormatters: widget._numbersOnly
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
            : null,
        decoration: InputDecoration(
          hintText: widget.hintText,
          helperText: widget.helperText,
          suffixIcon: widget._obscure
              ? IconButton(
                  icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
        ),
      ),
    );
  }
}
