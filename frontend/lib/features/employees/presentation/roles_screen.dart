import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../data/employee_models.dart';
import '../data/employee_providers.dart';

/// Role & permission matrix (spec §24) — "fully configurable, not
/// hard-coded in [the frontend]": every checkbox here edits data
/// (`Role.permissions`), never a compiled-in `if (role == ...)` branch
/// anywhere in the app. This is the read-only-for-System-roles caveat the
/// brief allows for — system roles are shown and editable in this demo
/// (a real deployment might lock the seeded ones); nothing here is faked.
class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  String? _selectedRoleId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rolesAsync = ref.watch(rolesProvider);

    return PageScaffold(
      title: l10n.fieldRole,
      showBackButton: true,
      backFallbackRoute: AppRoutes.employees,
      body: rolesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.unableToLoad)),
        data: (roles) {
          final selected = roles.firstWhere((r) => r.id == _selectedRoleId, orElse: () => roles.first);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              AppCard(
                title: Text(l10n.fieldRole),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in roles)
                      ChoiceChip(
                        label: Text(role.name),
                        selected: role.id == selected.id,
                        onSelected: (_) => setState(() => _selectedRoleId = role.id),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: AppCard(
                    title: Text('${selected.name} — ${l10n.fieldPermission}'),
                    child: _PermissionMatrix(role: selected),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PermissionMatrix extends ConsumerWidget {
  const _PermissionMatrix({required this.role});
  final Role role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {0: FlexColumnWidth(2)},
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.border))),
          children: [
            const SizedBox(),
            for (final action in PermissionCatalog.actions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(action, textAlign: TextAlign.center, style: AppTypography.tableHeader.copyWith(color: colors.textSecondary)),
              ),
          ],
        ),
        for (final module in PermissionCatalog.modules)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(module, style: AppTypography.body.copyWith(color: colors.textPrimary))),
              for (final action in PermissionCatalog.actions)
                Center(
                  child: !PermissionCatalog.supports(module, action)
                      ? const SizedBox(width: 24, height: 24)
                      : Checkbox(
                          value: role.permissions.contains(PermissionCatalog.key(module, action)),
                          onChanged: (checked) async {
                            final next = Set<String>.from(role.permissions);
                            final key = PermissionCatalog.key(module, action);
                            checked ?? false ? next.add(key) : next.remove(key);
                            // Awaited, and routed through the controller
                            // that bumps `rolesVersionProvider` — that's
                            // what makes the change visible beyond this
                            // screen. Un-ticking "products.view" for your
                            // own role now really does remove Products
                            // from the sidebar.
                            await ref.read(rolesVersionProvider.notifier).updatePermissions(role.id, next);
                          },
                        ),
                ),
            ],
          ),
      ],
    );
  }
}
