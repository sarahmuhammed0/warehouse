import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Phase 1.5 fix (found by the RTL verification test added while resolving
/// the Flutter toolchain issue — see docs/toolchain-fix.md).
///
/// Flutter's own built-in `GlobalMaterialLocalizations`/
/// `GlobalCupertinoLocalizations` delegates (from `flutter_localizations`)
/// do not ship a translation set for Kurdish (`ku`) — it isn't one of the
/// ~100 languages Flutter itself has translated framework strings ("OK",
/// "Cancel", date-picker labels, etc.) into. Without this fix, declaring
/// `ku` as a supported app locale is actually unsafe: the moment the
/// resolved locale is `ku`, `Localizations.localeOf(context)` returns `ku`,
/// no built-in delegate claims to support it, and *any* Material widget
/// that reads `MaterialLocalizations.of(context)` (which is most of them —
/// `TextField`, dialogs, etc., not just ones that show framework text)
/// throws `No MaterialLocalizations found` and crashes the tree. This is
/// exactly what the added widget test in `test/widget_test.dart` caught.
///
/// This is Flutter's own documented pattern for the situation
/// (https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
/// — "Advanced locale definition"): a small delegate that claims support
/// for the otherwise-unsupported locale and hands back an *existing*,
/// fully-supported locale's translations for the framework-level strings.
/// Arabic is the fallback — also RTL, so layout direction stays correct,
/// and it's the closest widely-supported language to Kurdish available in
/// Flutter's own translated set. This affects only generic framework
/// chrome (e.g. a date picker's "OK"/"Cancel"); every app-specific string
/// (`lib/l10n/app_ku.arb`, reached through `AppLocalizations.of(context)`)
/// still renders in actual Kurdish — unaffected by this file.
class KurdishMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const KurdishMaterialLocalizationsDelegate();

  static const _fallback = Locale('ar');

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(KurdishMaterialLocalizationsDelegate old) => false;
}

class KurdishCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const KurdishCupertinoLocalizationsDelegate();

  static const _fallback = Locale('ar');

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(KurdishCupertinoLocalizationsDelegate old) => false;
}
