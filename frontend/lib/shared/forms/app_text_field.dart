import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/validation/validators.dart' as validate;
import '../../l10n/generated/app_localizations.dart';
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
       _numbersOnly = false,
       _allowDecimal = false;

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
       _numbersOnly = false,
       _allowDecimal = false;

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
       _numbersOnly = true,
       _allowDecimal = allowDecimal;

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
       _numbersOnly = false,
       _allowDecimal = false;

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
  final bool _allowDecimal;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  /// `required: true` is what makes a field validate — not a second argument
  /// the caller also has to remember.
  ///
  /// It used to only draw the asterisk in [FormFieldWrapper], leaving the real
  /// check to a `validator: required(...)` passed alongside it. Most callers
  /// did pass one; the ones that forgot got a field marked with a red `*` that
  /// accepted empty and submitted silently — the worst of both, telling the
  /// user the field was mandatory and then disagreeing.
  ///
  /// The caller's own rule is asked first, and the generic required check only
  /// speaks when that rule is satisfied.
  ///
  /// That order is deliberate. A field that already says "Password is required."
  /// knows its own name and should keep saying it; replacing that with a generic
  /// "This field is required." would be a downgrade. The generic check is a
  /// floor for the fields that never had one, not a replacement for the ones
  /// that did.
  ///
  /// Rules that do not concern themselves with emptiness pass an empty value
  /// through — `positiveNumber()` returns null for it by design, with "combine
  /// with required() if mandatory" written next to it — so the required check is
  /// what answers, and the field is reported as missing rather than as holding a
  /// bad number it does not hold.
  FormFieldValidator<String>? _validator(BuildContext context) {
    if (!widget.required) return widget.validator;
    final message = AppLocalizations.of(context)?.requiredFieldMessage ?? 'This field is required.';
    final isRequired = validate.required(message);
    final caller = widget.validator;
    if (caller == null) return isRequired;
    return (value) => caller(value) ?? isRequired(value);
  }

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
        validator: _validator(context),
        // Submitting is not the only moment the border should be right: once
        // the field has been touched, correcting it clears the red as the user
        // types, instead of staying red until they submit again.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        // `allowDecimal` used to pick the on-screen keyboard and then be
        // discarded, so this filter accepted a '.' on a field that cannot use
        // one. On the stock adjustment dialog that was a silent no-op: typing
        // "2.5" left `int.tryParse` with null, the quantity became 0, and the
        // save returned without writing anything OR saying anything — the
        // dialog just sat there, which is one of the ways "adding stock does
        // nothing" was reported.
        inputFormatters: widget._numbersOnly
            ? [
                FilteringTextInputFormatter.allow(
                  widget._allowDecimal ? RegExp(r'[0-9.\-]') : RegExp(r'[0-9\-]'),
                ),
              ]
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
