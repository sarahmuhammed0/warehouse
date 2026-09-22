import 'package:flutter/material.dart';

/// Typography scale (architecture §27/§3). Named by *purpose*, not by size
/// — a screen asks for `AppTypography.pageTitle`, never a raw `fontSize:
/// 24`. No color is baked into these — callers pair them with a
/// `context.colors` token, since the same "page title" style needs a
/// different literal color in light vs. dark mode.
///
/// The scale is built around one idea from the FactoryOS design language:
/// **numbers are the loudest thing on the page.** A KPI's value gets real
/// display weight ([kpiValue], [kpiValueLarge]) while its label stays
/// small and muted, so a dashboard reads as a set of figures rather than a
/// set of captions. Everything that isn't a headline figure — body, table
/// text, form labels — stays tight and quiet, because this is a daily-use
/// business tool where most of the screen is data, not headings.
class AppTypography {
  AppTypography._();

  /// The largest text in the product — a dashboard's welcome header. Used
  /// once per screen at most.
  static const TextStyle displayTitle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.18,
    letterSpacing: -0.6,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.22,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// The muted one-liner under a card title ("Completed sales today").
  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// A stat card's number.
  static const TextStyle kpiValue = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.5,
  );

  /// The headline figure on a brand panel — the one number a screen is
  /// really about.
  static const TextStyle kpiValueLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.8,
  );

  /// The small muted caption under a KPI value.
  static const TextStyle kpiLabel = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Small caps eyebrow — the label riding above a headline figure on a
  /// brand panel.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.9,
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
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.3,
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
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
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
      headlineMedium: displayTitle.copyWith(color: textColor),
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
