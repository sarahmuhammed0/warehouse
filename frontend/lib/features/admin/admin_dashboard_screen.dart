import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/placeholders/module_placeholder_screen.dart';

/// System Admin area (§56) — kept separate from the business app's shell
/// entirely (see `routing/app_router.dart`'s second `ShellRoute`). No
/// System Admin functionality is implemented yet (§27).
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ModulePlaceholderScreen(
      moduleLabel: l10n.adminNavDashboard,
      icon: Icons.admin_panel_settings_outlined,
    );
  }
}
