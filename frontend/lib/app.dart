import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'localization/app_locales.dart';
import 'localization/kurdish_localizations_fallback.dart';
import 'localization/locale_controller.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// Root widget. The app shell re-brands itself with the authenticated
/// business's own name once logged in (§24) — see
/// `routing/app_router.dart`'s `_businessBrandLabel`.
class WarehouseOsApp extends ConsumerWidget {
  const WarehouseOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Warehouse OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      routerConfig: router,
      // Kurdish delegates must come first: Localizations picks the first
      // delegate in the list whose isSupported(locale) is true for each
      // localization type, and Flutter's own Global*Localizations.delegate
      // (inside AppLocalizations.localizationsDelegates) doesn't support
      // `ku` at all — see localization/kurdish_localizations_fallback.dart.
      localizationsDelegates: [
        const KurdishMaterialLocalizationsDelegate(),
        const KurdishCupertinoLocalizationsDelegate(),
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        // Explicit RTL resolution (§21/§20) rather than relying solely on
        // Flutter's built-in per-language RTL table — see
        // `localization/app_locales.dart`'s doc comment for why: Flutter
        // does not reliably know a bare `ku` tag is RTL on its own. The
        // resolved locale (explicit choice, or the device's, once matched
        // against `supportedLocales`) decides direction for the whole tree.
        final resolvedLocale = Localizations.localeOf(context);
        final direction = AppLocales.directionFor(resolvedLocale);
        return Directionality(textDirection: direction, child: child ?? const SizedBox.shrink());
      },
    );
  }
}
