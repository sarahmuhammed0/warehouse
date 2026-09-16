/// Form-validation foundation (architecture §30). Plain functions matching
/// `FormFieldValidator<String>`'s signature (`String? Function(String?)`),
/// composable with [combine] — later feature forms (Products, Customers,
/// Orders, ...) reuse these instead of re-implementing "is this required" in
/// every screen. Business-specific rules (duplicate SKU, valid business
/// phone format, etc.) are added per-feature on top of these, not here.
library;

typedef Validator = String? Function(String? value);

Validator required([String message = 'This field is required.']) {
  return (value) => (value == null || value.trim().isEmpty) ? message : null;
}

Validator minLength(int length, [String? message]) {
  return (value) {
    if (value == null || value.trim().length < length) {
      return message ?? 'Must be at least $length characters.';
    }
    return null;
  };
}

Validator maxLength(int length, [String? message]) {
  return (value) {
    if (value != null && value.length > length) {
      return message ?? 'Must be $length characters or fewer.';
    }
    return null;
  };
}

final _phonePattern = RegExp(r'^\+?[0-9\s\-()]{7,20}$');

Validator phone([String message = 'Enter a valid phone number.']) {
  return (value) {
    if (value == null || value.trim().isEmpty) return null; // combine with required() if mandatory
    return _phonePattern.hasMatch(value.trim()) ? null : message;
  };
}

Validator positiveNumber([String message = 'Must be a positive number.']) {
  return (value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = num.tryParse(value.trim());
    if (parsed == null || parsed < 0) return message;
    return null;
  };
}

/// Runs [validators] in order, returning the first non-null error message.
Validator combine(List<Validator> validators) {
  return (value) {
    for (final validator in validators) {
      final result = validator(value);
      if (result != null) return result;
    }
    return null;
  };
}
