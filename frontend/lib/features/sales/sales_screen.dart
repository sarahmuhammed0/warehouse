import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/placeholders/module_placeholder_screen.dart';

class SalesPlaceholderScreen extends StatelessWidget {
  const SalesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ModulePlaceholderScreen(moduleLabel: l10n.navSales, icon: Icons.point_of_sale_outlined);
  }
}
