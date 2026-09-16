import 'package:flutter/material.dart';

/// Typography scale (architecture §27/§3). Named by *purpose*, not by size
/// — a screen asks for `AppTypography.pageTitle`, never a raw `fontSize:
/// 24`. Deliberately restrained sizes throughout: §2's design direction
/// explicitly rules out "huge typography" for what is a daily-use business
/// tool, not a marketing page. No color is baked into these — callers pair
/// them with a `context.colors` token, since the same "page title" style
/// needs a different literal color in light vs. dark mode.
class AppTypography {
  AppTypography._();

  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const TextStyle formLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle helperText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle tableHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.2,
  );

  static const TextStyle tableText = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const TextStyle navLabel = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  static const TextStyle statusBadge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.4,
  );

  /// Builds a Material [TextTheme] from the above, so standard widgets
  /// (AppBar title, default button labels, etc.) that read
  /// `Theme.of(context).textTheme` automatically match this scale too —
  /// shared widgets should still prefer the named styles above directly
  /// when the semantic mapping below isn't a perfect fit.
  static TextTheme textTheme(Color textColor) {
    return TextTheme(
      headlineSmall: pageTitle.copyWith(color: textColor),
      titleLarge: sectionTitle.copyWith(color: textColor),
      titleMedium: cardTitle.copyWith(color: textColor),
      bodyMedium: body.copyWith(color: textColor),
      bodySmall: caption.copyWith(color: textColor),
      labelLarge: button.copyWith(color: textColor),
      labelMedium: label.copyWith(color: textColor),
      labelSmall: helperText.copyWith(color: textColor),
    );
  }
}
