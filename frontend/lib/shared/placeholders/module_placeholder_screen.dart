import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../feedback/app_empty_state.dart';
import '../layout/page_scaffold.dart';

/// The screen every not-yet-built module points its route at (§7: "Each
/// navigation destination should have a clean placeholder screen/component
/// that clearly indicates the future module without fake business data").
/// Built on the same [PageScaffold] a real module screen will use, so
/// replacing this with the real screen later is a body swap, not a rewrite
/// of the page chrome.
class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({super.key, required this.moduleLabel, required this.icon});

  final String moduleLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PageScaffold(
      title: moduleLabel,
      body: AppEmptyState(
        icon: icon,
        title: l10n.moduleComingSoonTitle(moduleLabel),
        description: l10n.moduleComingSoonDescription(moduleLabel),
      ),
    );
  }
}
