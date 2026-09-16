import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../localization/app_locales.dart';
import '../../localization/locale_controller.dart';
import '../../shared/cards/app_card.dart';
import '../../shared/feedback/app_empty_state.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/theme_controller.dart';

/// Settings is a placeholder module like the other 15 (§7) — no business
/// settings (§34's numbering/PDF/inventory rules etc.) exist yet. The one
/// exception: a small, clearly-labeled "Appearance (preview)" section that
/// exercises the real theme/locale providers built for §4/§24, so the
/// theme/RTL foundation is verifiable by actually using the app, not only
/// by reading code. This is a foundation demo, not real Settings
/// functionality — nothing here persists anywhere.
class SettingsPlaceholderScreen extends ConsumerWidget {
  const SettingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return PageScaffold(
      title: l10n.navSettings,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.lg,
        children: [
          AppCard(
            title: const Text('Appearance (foundation preview)'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.md,
              children: [
                Text(
                  'Demonstrates the theme/locale foundation built in Phase 1 — not real Settings, nothing here is saved.',
                  style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final mode in ThemeMode.values)
                      ChoiceChip(
                        label: Text(mode.name),
                        selected: themeMode == mode,
                        onSelected: (_) => ref.read(themeModeProvider.notifier).setMode(mode),
                      ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('System'),
                      selected: locale == null,
                      onSelected: (_) => ref.read(localeProvider.notifier).setLocale(null),
                    ),
                    for (final appLocale in AppLocales.all)
                      ChoiceChip(
                        label: Text(appLocale.label),
                        selected: locale?.languageCode == appLocale.locale.languageCode,
                        onSelected: (_) => ref.read(localeProvider.notifier).setLocale(appLocale.locale),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const AppEmptyState(
            icon: Icons.settings_outlined,
            title: 'Business settings are coming in a later phase',
            description:
                'Business profile, users & roles, inventory rules, sales/PDF numbering, and security settings will connect to the backend once those modules are built.',
          ),
        ],
      ),
    );
  }
}
