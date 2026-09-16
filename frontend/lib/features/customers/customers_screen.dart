import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/placeholders/module_placeholder_screen.dart';

class CustomersPlaceholderScreen extends StatelessWidget {
  const CustomersPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ModulePlaceholderScreen(moduleLabel: l10n.navCustomers, icon: Icons.people_outline);
  }
}
