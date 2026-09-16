import 'package:flutter/widgets.dart';

/// The three languages the specification requires (§20): English, Arabic,
/// Kurdish (Badini). Metadata lives in one place — nothing else in the app
/// hard-codes a locale code or guesses RTL-ness from it.
///
/// ASSUMPTION (flagged, not silently decided): Kurdish Badini has no
/// distinct, widely-adopted ISO 639-1 code separate from generic Kurdish
/// (`ku`). This project uses the plain `ku` language code for the Badini
/// ARB file (`lib/l10n/app_ku.arb`). Badini is written in Arabic script and
/// is RTL — that is captured explicitly via [AppLocale.isRtl] below, not
/// inferred from the language code (Flutter's own built-in RTL-language
/// table does not reliably know a bare `ku` tag is RTL, since Kurdish is
/// written in Latin script in other regions/dialects — see
/// `docs/localization.md` for the full reasoning). Confirm the exact
/// locale/script convention with a native reviewer before this ships
/// user-facing translations.
class AppLocale {
  const AppLocale({required this.locale, required this.label, required this.isRtl});

  final Locale locale;
  final String label;
  final bool isRtl;
}

class AppLocales {
  AppLocales._();

  static const english = AppLocale(locale: Locale('en'), label: 'English', isRtl: false);
  static const arabic = AppLocale(locale: Locale('ar'), label: 'العربية', isRtl: true);
  static const kurdishBadini = AppLocale(locale: Locale('ku'), label: 'کوردی بادینی', isRtl: true);

  static const List<AppLocale> all = [english, arabic, kurdishBadini];

  static const List<Locale> supportedLocales = [Locale('en'), Locale('ar'), Locale('ku')];

  static bool isRtlLocale(Locale locale) {
    for (final entry in all) {
      if (entry.locale.languageCode == locale.languageCode) return entry.isRtl;
    }
    return false;
  }

  static TextDirection directionFor(Locale locale) =>
      isRtlLocale(locale) ? TextDirection.rtl : TextDirection.ltr;
}
