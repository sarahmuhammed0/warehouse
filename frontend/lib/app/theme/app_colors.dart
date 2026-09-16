import 'package:flutter/material.dart';

/// Color tokens (architecture §27's design-token strategy, translated to
/// Flutter's ColorScheme rather than CSS custom properties — this is the
/// Flutter-idiomatic equivalent of the React build's `tokens.css`). Kept
/// deliberately small and business-utilitarian: §41 explicitly asks for
/// clarity over decoration.
class AppColors {
  AppColors._();

  static const Color accent = Color(0xFF1C5F8F);
  static const Color success = Color(0xFF276B48);
  static const Color danger = Color(0xFFA8431C);
}
