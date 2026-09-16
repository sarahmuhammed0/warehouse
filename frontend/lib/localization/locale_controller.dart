import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_locales.dart';

/// Locale state (architecture §20/§24) — in-memory only, same reasoning as
/// [ThemeModeController]: Settings doesn't exist yet to persist a choice.
/// `null` means "follow the device locale" (MaterialApp's default
/// resolution against [AppLocales.supportedLocales]).
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void setLocale(Locale? locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);
