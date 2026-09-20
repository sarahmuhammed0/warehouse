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
import '../../shared/feedback/confirm_dialog.dart';
import '../../shared/forms/app_text_field.dart';
import '../../shared/forms/selection_controls.dart';
import '../../shared/layout/page_scaffold.dart';
import '../../shared/layout/responsive/responsive_layout.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/theme_controller.dart';
import 'data/business_type_config.dart';
import 'data/settings_state.dart';

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
    final colors = context.colors;

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

    final nav = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in sections.entries)
          ListTile(
            selected: _section == entry.key,
            selectedTileColor: colors.selectedBg,
            leading: Icon(entry.value.$1, size: 20),
            title: Text(entry.value.$2, style: AppTypography.body),
            onTap: () => setState(() => _section = entry.key),
          ),
      ],
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
          AppTextField(label: l10n.fieldName, controller: TextEditingController(text: settings.businessName), onChanged: (v) => controller.update((s) => s.copyWith(businessName: v))),
          AppTextField(label: 'Currency', controller: TextEditingController(text: settings.currency), onChanged: (v) => controller.update((s) => s.copyWith(currency: v))),
          const Divider(),
          Text('Business type (spec §33) — determines which sidebar modules are enabled.', style: AppTypography.helperText),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in BusinessType.values)
                ChoiceChip(
                  label: Text(type.name),
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
          AppTextField.number(
            label: l10n.fieldReorderLevel,
            controller: TextEditingController(text: '${settings.lowStockDefaultThreshold}'),
            allowDecimal: false,
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
            SizedBox(width: 160, child: AppTextField(label: 'Invoice prefix', controller: TextEditingController(text: settings.invoicePrefix), onChanged: (v) => controller.update((s) => s.copyWith(invoicePrefix: v)))),
            SizedBox(width: 160, child: AppTextField(label: 'Order prefix', controller: TextEditingController(text: settings.orderPrefix), onChanged: (v) => controller.update((s) => s.copyWith(orderPrefix: v)))),
            SizedBox(width: 160, child: AppTextField.number(label: 'Starting number', controller: TextEditingController(text: '${settings.startingNumber}'), allowDecimal: false, onChanged: (v) => controller.update((s) => s.copyWith(startingNumber: int.tryParse(v) ?? s.startingNumber)))),
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
          AppTextField.multiline(label: 'Footer text', controller: TextEditingController(text: settings.pdfFooterText), maxLines: 2, onChanged: (v) => controller.update((s) => s.copyWith(pdfFooterText: v))),
          const Divider(),
          Text('Live preview', style: AppTypography.sectionTitle),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: context.colors.border), borderRadius: BorderRadius.circular(8)),
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
      child: AppTextField(label: 'Production number prefix', controller: TextEditingController(text: settings.productionNumberPrefix), onChanged: (v) => controller.update((s) => s.copyWith(productionNumberPrefix: v))),
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
          AppTextField.number(label: 'Minimum password length', controller: TextEditingController(text: '${settings.minPasswordLength}'), allowDecimal: false, onChanged: (v) => controller.update((s) => s.copyWith(minPasswordLength: int.tryParse(v) ?? s.minPasswordLength))),
          AppTextField.number(label: 'Session timeout (minutes)', controller: TextEditingController(text: '${settings.sessionTimeoutMinutes}'), allowDecimal: false, onChanged: (v) => controller.update((s) => s.copyWith(sessionTimeoutMinutes: int.tryParse(v) ?? s.sessionTimeoutMinutes))),
          AppTextField.number(label: 'Lockout after N failed logins', controller: TextEditingController(text: '${settings.loginLockoutAttempts}'), allowDecimal: false, onChanged: (v) => controller.update((s) => s.copyWith(loginLockoutAttempts: int.tryParse(v) ?? s.loginLockoutAttempts))),
          Text('The backend\'s real auth already enforces lockout/rate-limiting (Phase 2) — this panel is the future UI for adjusting those thresholds per business, not yet wired to that endpoint.', style: AppTypography.helperText),
        ],
      ),
    );
  }
}

class _CustomFieldsSection extends StatefulWidget {
  const _CustomFieldsSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  State<_CustomFieldsSection> createState() => _CustomFieldsSectionState();
}

class _CustomFieldsSectionState extends State<_CustomFieldsSection> {
  final List<String> _fields = ['Wood type', 'Fabric type'];
  final _newField = TextEditingController();

  @override
  void dispose() {
    _newField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: Text(widget.l10n.settingsCustomFieldsLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          for (final field in _fields)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune),
              title: Text(field),
              trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _fields.remove(field))),
            ),
          Row(
            children: [
              Expanded(child: AppTextField(label: widget.l10n.fieldName, controller: _newField)),
              const SizedBox(width: 8),
              AppButton(
                label: widget.l10n.add,
                onPressed: () {
                  if (_newField.text.trim().isEmpty) return;
                  setState(() {
                    _fields.add(_newField.text.trim());
                    _newField.clear();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: Text(l10n.settingsBackupLabel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Row(
            children: [
              AppButton(label: 'Backup now', icon: Icons.backup_outlined, onPressed: () => _showBackupConfirmation(context, l10n)),
              const SizedBox(width: 12),
              AppButton(label: 'Restore', icon: Icons.restore_outlined, variant: AppButtonVariant.outline, onPressed: () => _showRestoreWarning(context, l10n)),
            ],
          ),
          const Divider(),
          Text('Backup history', style: AppTypography.sectionTitle),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Scheduled backup'),
            subtitle: const Text('Yesterday, 02:00'),
            trailing: StatusBadge(label: l10n.statusCompleted, tone: StatusTone.success),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupConfirmation(BuildContext context, AppLocalizations l10n) async {
    await confirmAction(context, title: 'Start a manual backup?', description: l10n.demoDataNotice, confirmLabel: 'Backup now', cancelLabel: l10n.cancel);
  }

  Future<void> _showRestoreWarning(BuildContext context, AppLocalizations l10n) async {
    await confirmAction(context, title: 'Restore from backup?', description: 'This will overwrite current data once connected to a real backup engine. ${l10n.demoDataNotice}', confirmLabel: 'Restore', cancelLabel: l10n.cancel, isDestructive: true);
  }
}
