import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../localization/app_locales.dart';
import '../../localization/locale_controller.dart';
import '../../routing/app_routes.dart';
import '../../shared/badges/status_badge.dart';
import '../../shared/buttons/app_button.dart';
import '../../shared/cards/app_card.dart';
import '../../core/error/failure.dart';
import '../../shared/feedback/app_toast.dart';
import '../../shared/feedback/confirm_dialog.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/forms/selection_controls.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/layout/responsive/responsive_layout.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/theme_controller.dart';
import 'data/business_type_config.dart';
import 'data/backup_repository.dart';
import 'data/custom_fields_repository.dart';
import 'data/settings_state.dart';
import 'presentation/settings_field.dart';

enum _SettingsSection { general, business, users, inventory, sales, pdf, production, security, customFields, backup }

/// Settings (spec §32/§34) — real, interactive section UI over an in-memory
/// draft (`businessSettingsProvider`); nothing persists to a backend yet
/// (§48/§35's own precedent — same as the theme/locale foundation).
class SettingsPlaceholderScreen extends ConsumerStatefulWidget {
  const SettingsPlaceholderScreen({super.key});

  @override
  ConsumerState<SettingsPlaceholderScreen> createState() => _SettingsPlaceholderScreenState();
}

class _SettingsPlaceholderScreenState extends ConsumerState<SettingsPlaceholderScreen> {
  _SettingsSection _section = _SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final sections = <_SettingsSection, (IconData, String)>{
      _SettingsSection.general: (Icons.palette_outlined, 'Appearance'),
      _SettingsSection.business: (Icons.business_outlined, l10n.navSettings),
      _SettingsSection.users: (Icons.people_outline, l10n.navEmployees),
      _SettingsSection.inventory: (Icons.warehouse_outlined, l10n.navInventory),
      _SettingsSection.sales: (Icons.point_of_sale_outlined, l10n.navSales),
      _SettingsSection.pdf: (Icons.picture_as_pdf_outlined, l10n.pdfTemplateBuilderLabel),
      _SettingsSection.production: (Icons.precision_manufacturing_outlined, l10n.navProduction),
      _SettingsSection.security: (Icons.security_outlined, l10n.settingsSecurityLabel),
      _SettingsSection.customFields: (Icons.tune, l10n.settingsCustomFieldsLabel),
      _SettingsSection.backup: (Icons.backup_outlined, l10n.settingsBackupLabel),
    };

    // A settings index is navigation, not data — so it gets the sidebar's
    // pill language rather than a stack of `ListTile`s, and sits on its own
    // card so the selected pill has a surface to be selected *on* (§20).
    final nav = AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in sections.entries)
            _SectionTile(
              icon: entry.value.$1,
              label: entry.value.$2,
              selected: _section == entry.key,
              onTap: () => setState(() => _section = entry.key),
            ),
        ],
      ),
    );

    final content = switch (_section) {
      _SettingsSection.general => _GeneralSection(l10n: l10n),
      _SettingsSection.business => _BusinessSection(l10n: l10n),
      _SettingsSection.users => _UsersSection(l10n: l10n),
      _SettingsSection.inventory => _InventorySection(l10n: l10n),
      _SettingsSection.sales => _SalesSection(l10n: l10n),
      _SettingsSection.pdf => _PdfSection(l10n: l10n),
      _SettingsSection.production => _ProductionSection(l10n: l10n),
      _SettingsSection.security => _SecuritySection(l10n: l10n),
      _SettingsSection.customFields => _CustomFieldsSection(l10n: l10n),
      _SettingsSection.backup => _BackupSection(l10n: l10n),
    };

    return PageScaffold(
      title: l10n.navSettings,
      showBackButton: true,
      backFallbackRoute: AppRoutes.dashboard,
      body: ResponsiveLayout(
        mobile: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            SizedBox(height: 260, child: SingleChildScrollView(child: nav)),
            content,
          ],
        ),
        desktop: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 220, child: nav),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// One entry in the settings index. Same pill as `AppSidebar`'s nav tile —
/// this is the same kind of control doing the same job one level down, and
/// it would be strange for the two to look different.
class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.primary : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? colors.selectedBg : Colors.transparent,
        borderRadius: AppRadius.mdRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.navLabel.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return AppCard(
      title: const Text('Appearance'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.md,
        children: [
          Wrap(spacing: AppSpacing.sm, children: [for (final mode in ThemeMode.values) ChoiceChip(label: Text(mode.name), selected: themeMode == mode, onSelected: (_) => ref.read(themeModeProvider.notifier).setMode(mode))]),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(label: const Text('System'), selected: locale == null, onSelected: (_) => ref.read(localeProvider.notifier).setLocale(null)),
              for (final appLocale in AppLocales.all)
                ChoiceChip(label: Text(appLocale.label), selected: locale?.languageCode == appLocale.locale.languageCode, onSelected: (_) => ref.read(localeProvider.notifier).setLocale(appLocale.locale)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessSection extends ConsumerWidget {
  const _BusinessSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.fieldName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          SettingsField(label: l10n.fieldName, initialValue: settings.businessName, onChanged: (v) => controller.update((s) => s.copyWith(businessName: v))),
          SettingsField(label: 'Currency', initialValue: settings.currency, onChanged: (v) => controller.update((s) => s.copyWith(currency: v))),
          const Divider(),
          // Two things were being shown to the user that were never meant for
          // them: an internal specification reference, and the Dart enum's own
          // identifiers — "furnitureFactory" rather than "Furniture Factory".
          Text('Business type — determines which modules are enabled.', style: AppTypography.helperText),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in BusinessType.values)
                ChoiceChip(
                  label: Text(businessTypeLabel(type)),
                  selected: ref.watch(businessTypeProvider) == type,
                  onSelected: (_) => ref.read(businessTypeProvider.notifier).set(type),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsersSection extends StatelessWidget {
  const _UsersSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: Text(l10n.navEmployees),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text('User/role/permission management lives in its own module.', style: AppTypography.body),
          AppButton(label: l10n.navEmployees, icon: Icons.arrow_forward, variant: AppButtonVariant.secondary, onPressed: () => context.go(AppRoutes.employees)),
        ],
      ),
    );
  }
}

class _InventorySection extends ConsumerWidget {
  const _InventorySection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.navInventory),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          AppSwitch(
            label: 'Allow negative inventory',
            helperText: 'Off by default — only this business\'s own settings can enable it (never forced on by System Admin).',
            value: settings.negativeInventoryAllowed,
            onChanged: (v) => controller.update((s) => s.copyWith(negativeInventoryAllowed: v)),
          ),
          SettingsField(
            label: l10n.fieldReorderLevel,
            initialValue: '${settings.lowStockDefaultThreshold}',
            number: true,
            onChanged: (v) => controller.update((s) => s.copyWith(lowStockDefaultThreshold: int.tryParse(v) ?? s.lowStockDefaultThreshold)),
          ),
        ],
      ),
    );
  }
}

class _SalesSection extends ConsumerWidget {
  const _SalesSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.navSales),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          Wrap(spacing: 14, runSpacing: 14, children: [
            SizedBox(width: 160, child: SettingsField(label: 'Invoice prefix', initialValue: settings.invoicePrefix, onChanged: (v) => controller.update((s) => s.copyWith(invoicePrefix: v)))),
            SizedBox(width: 160, child: SettingsField(label: 'Order prefix', initialValue: settings.orderPrefix, onChanged: (v) => controller.update((s) => s.copyWith(orderPrefix: v)))),
            SizedBox(width: 160, child: SettingsField(label: 'Starting number', initialValue: '${settings.startingNumber}', number: true, onChanged: (v) => controller.update((s) => s.copyWith(startingNumber: int.tryParse(v) ?? s.startingNumber)))),
          ]),
          Text('Preview: ${settings.invoicePrefix}-2026-${settings.startingNumber.toString().padLeft(6, '0')}', style: AppTypography.helperText),
          AppCheckbox(label: l10n.paymentMethodCash, value: settings.cashPaymentsEnabled, onChanged: (v) => controller.update((s) => s.copyWith(cashPaymentsEnabled: v ?? true))),
          AppCheckbox(label: l10n.paymentMethodBankTransfer, value: settings.bankTransferEnabled, onChanged: (v) => controller.update((s) => s.copyWith(bankTransferEnabled: v ?? true))),
          AppCheckbox(label: l10n.paymentMethodCard, value: settings.cardPaymentsEnabled, onChanged: (v) => controller.update((s) => s.copyWith(cardPaymentsEnabled: v ?? false))),
        ],
      ),
    );
  }
}

class _PdfSection extends ConsumerWidget {
  const _PdfSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.pdfTemplateBuilderLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          AppCheckbox(label: l10n.fieldImage, value: settings.pdfShowLogo, onChanged: (v) => controller.update((s) => s.copyWith(pdfShowLogo: v ?? true))),
          AppCheckbox(label: l10n.fieldTax, value: settings.pdfShowTaxInfo, onChanged: (v) => controller.update((s) => s.copyWith(pdfShowTaxInfo: v ?? true))),
          AppCheckbox(label: 'Signature', value: settings.pdfShowSignature, onChanged: (v) => controller.update((s) => s.copyWith(pdfShowSignature: v ?? true))),
          SettingsField(label: 'Footer text', initialValue: settings.pdfFooterText, maxLines: 2, onChanged: (v) => controller.update((s) => s.copyWith(pdfFooterText: v))),
          const Divider(),
          Text('Live preview', style: AppTypography.sectionTitle),
          // A preview nested inside a settings card is exactly what
          // `AppPanel` is for — a muted well, not a second bordered box
          // (§33: not every element needs a card).
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                if (settings.pdfShowLogo) const Text('[Logo]'),
                Text(ref.watch(businessSettingsProvider).businessName, style: AppTypography.sectionTitle),
                if (settings.pdfShowTaxInfo) const Text('Tax #: —'),
                const Divider(),
                Text(settings.pdfFooterText, style: AppTypography.caption),
                if (settings.pdfShowSignature) const Text('_________________ Signature'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionSection extends ConsumerWidget {
  const _ProductionSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.navProduction),
      child: SettingsField(label: 'Production number prefix', initialValue: settings.productionNumberPrefix, onChanged: (v) => controller.update((s) => s.copyWith(productionNumberPrefix: v))),
    );
  }
}

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(businessSettingsProvider);
    final controller = ref.read(businessSettingsProvider.notifier);
    return AppCard(
      title: Text(l10n.settingsSecurityLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          SettingsField(label: 'Minimum password length', initialValue: '${settings.minPasswordLength}', number: true, onChanged: (v) => controller.update((s) => s.copyWith(minPasswordLength: int.tryParse(v) ?? s.minPasswordLength))),
          SettingsField(label: 'Session timeout (minutes)', initialValue: '${settings.sessionTimeoutMinutes}', number: true, onChanged: (v) => controller.update((s) => s.copyWith(sessionTimeoutMinutes: int.tryParse(v) ?? s.sessionTimeoutMinutes))),
          SettingsField(label: 'Lockout after N failed logins', initialValue: '${settings.loginLockoutAttempts}', number: true, onChanged: (v) => controller.update((s) => s.copyWith(loginLockoutAttempts: int.tryParse(v) ?? s.loginLockoutAttempts))),
          Text('The backend\'s real auth already enforces lockout/rate-limiting (Phase 2) — this panel is the future UI for adjusting those thresholds per business, not yet wired to that endpoint.', style: AppTypography.helperText),
        ],
      ),
    );
  }
}

class _CustomFieldsSection extends ConsumerStatefulWidget {
  const _CustomFieldsSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  ConsumerState<_CustomFieldsSection> createState() => _CustomFieldsSectionState();
}

class _CustomFieldsSectionState extends ConsumerState<_CustomFieldsSection> {
  final _newField = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newField.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CustomFieldsRepository repo) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(customFieldsRepositoryProvider));
      ref.invalidate(customFieldsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = ref.watch(customFieldsProvider);
    return AppCard(
      title: Text(widget.l10n.settingsCustomFieldsLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          for (final field in fields.asData?.value ?? const <CustomFieldDefinition>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: Text(field.label),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: _busy ? null : () => _run((repo) => repo.delete(field.id)),
              ),
            ),
          Row(
            children: [
              Expanded(child: AppTextField(label: widget.l10n.fieldName, controller: _newField)),
              const SizedBox(width: 8),
              AppButton(
                label: widget.l10n.add,
                onPressed: _busy
                    ? null
                    : () {
                        final label = _newField.text.trim();
                        if (label.isEmpty) return;
                        _newField.clear();
                        _run((repo) => repo.create(label));
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// §33's backup controls.
///
/// The history is whatever the server has actually recorded — nothing is
/// invented here. It is empty for a business owner, because backups dump a
/// database holding every tenant and are therefore a platform operation; the
/// buttons below report the server's own refusal rather than pretending.
class _BackupSection extends ConsumerWidget {
  const _BackupSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(backupHistoryProvider).asData?.value ?? const <BackupRecord>[];
    return AppCard(
      title: Text(l10n.settingsBackupLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            children: [
              AppButton(label: 'Backup now', icon: Icons.backup_outlined, onPressed: () => _startBackup(context, ref)),
              const SizedBox(width: 12),
              AppButton(label: 'Restore', icon: Icons.restore_outlined, variant: AppButtonVariant.outline, onPressed: () => _showRestoreWarning(context, l10n)),
            ],
          ),
          const Divider(),
          Text('Backup history', style: AppTypography.sectionTitle),
          if (history.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('No backups recorded'),
              subtitle: const Text('Backups are run by the platform administrator.'),
            )
          else
            for (final record in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(record.status == 'completed' ? Icons.check_circle_outline : Icons.schedule_outlined),
                title: Text(_timestamp(record.createdAt)),
                subtitle: Text(record.note ?? '—'),
                trailing: StatusBadge(
                  label: record.status,
                  tone: record.status == 'completed'
                      ? StatusTone.success
                      : record.status == 'failed'
                          ? StatusTone.danger
                          : StatusTone.warning,
                ),
              ),
        ],
      ),
    );
  }

  static String _timestamp(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _startBackup(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Start a manual backup?',
      description: 'The request is recorded on the server. No file is written until a backup target is configured.',
      confirmLabel: 'Backup now',
      cancelLabel: l10n.cancel,
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final outcome = await ref.read(backupRepositoryProvider).start();
      if (!context.mounted) return;
      ref.invalidate(backupHistoryProvider);
      // Never "Backup complete". The server said whether a file exists, and
      // that is what is repeated here.
      if (outcome.fileProduced) {
        AppToast.success(context, outcome.message);
      } else {
        AppToast.warning(context, outcome.message);
      }
    } on Failure catch (e) {
      if (context.mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _showRestoreWarning(BuildContext context, AppLocalizations l10n) async {
    final confirmed = await confirmAction(
      context,
      title: 'Restore from backup?',
      description: 'This would overwrite every business’s data. There is nothing to restore from — no backup file has been written.',
      confirmLabel: 'Restore',
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (confirmed == true && context.mounted) {
      AppToast.warning(context, 'Restore is unavailable: no backup file exists to restore from.');
    }
  }
}
