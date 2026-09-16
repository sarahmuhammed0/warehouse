import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/placeholders/module_placeholder_screen.dart';

class ProductsPlaceholderScreen extends StatelessWidget {
  const ProductsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ModulePlaceholderScreen(moduleLabel: l10n.navProducts, icon: Icons.inventory_2_outlined);
  }
}
