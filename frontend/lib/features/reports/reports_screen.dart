import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/placeholders/module_placeholder_screen.dart';

class ReportsPlaceholderScreen extends StatelessWidget {
  const ReportsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ModulePlaceholderScreen(moduleLabel: l10n.navReports, icon: Icons.bar_chart_outlined);
  }
}
