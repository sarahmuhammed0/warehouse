import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget. Real branding (a logged-in business's own logo/name, per
/// architecture §4) replaces the static title once Phase 1's business
/// context exists — Phase 0 has no tenant to brand for yet.
class WarehouseOsApp extends StatelessWidget {
  const WarehouseOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Warehouse OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
