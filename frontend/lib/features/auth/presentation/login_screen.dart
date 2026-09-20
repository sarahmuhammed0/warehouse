import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../data/demo_auth_repository.dart';
import 'providers/auth_controller.dart';
import 'providers/auth_state.dart';

/// The real login screen (Phase 2 §17), replacing Phase 1's
/// `LoginPlaceholderScreen`. Phone + password against the actual backend
/// — no hardcoded credentials, no bypass, no fake success (§38). Business
/// branding cannot be shown here (§24): which business a phone belongs to
/// is only known AFTER a successful login (see docs/authentication.md
/// "Phone uniqueness" for why), so this screen shows generic product
/// branding only; `AppShell`'s sidebar re-brands itself with the
/// authenticated business's own name once logged in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  // Iraq is the UI default (§14) — the backend itself has no notion of a
  // default country and validates whatever E.164 string arrives (see
  // backend/src/utils/phone.js's doc comment).
  final _phoneController = TextEditingController(text: '+964');
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(authControllerProvider.notifier).clearError();
    if (!_formKey.currentState!.validate()) return;
    ref.read(authControllerProvider.notifier).login(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _continueAsDemo(String phone) {
    ref.read(authControllerProvider.notifier).clearError();
    ref.read(authControllerProvider.notifier).login(phone: phone, password: kDemoPassword);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authControllerProvider);
    final isAuthenticating = authState is AuthAuthenticating;

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.lg,
              children: [
                _Branding(colors: colors, l10n: l10n),
                if (authState is AuthSessionExpired)
                  _Banner(message: l10n.sessionExpiredMessage, tone: _BannerTone.info),
                if (AppModeConfig.isDemo)
                  _DemoModeCard(l10n: l10n, isAuthenticating: isAuthenticating, onContinue: _continueAsDemo),
                if (AppModeConfig.isDemo)
                  Row(
                    children: [
                      Expanded(child: Divider(color: colors.border)),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Text(
                            l10n.demoModeOrDivider,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: colors.border)),
                    ],
                  ),
                AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacing.md,
                      children: [
                        AppTextField(
                          label: l10n.phoneNumber,
                          controller: _phoneController,
                          required: true,
                          keyboardType: TextInputType.phone,
                          enabled: !isAuthenticating,
                          validator: combine([required(l10n.phoneRequired), phone()]),
                        ),
                        AppTextField.password(
                          label: l10n.password,
                          controller: _passwordController,
                          required: true,
                          enabled: !isAuthenticating,
                          validator: required(l10n.passwordRequired),
                        ),
                        if (authState is AuthError)
                          _Banner(message: authState.message, tone: _BannerTone.error),
                        AppButton(
                          key: const ValueKey('loginSubmitButton'),
                          label: l10n.login,
                          onPressed: isAuthenticating ? null : _submit,
                          loading: isAuthenticating,
                          expand: true,
                        ),
                      ],
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

/// The demo entry points (§2/§6 of the frontend-demo-mode brief; §16/§17 of
/// the roles-and-permissions brief) — only rendered when `AppModeConfig.
/// isDemo`, never in backend mode. Every button here calls the exact same
/// `AuthController.login()` the real form uses; `DemoAuthRepository` is
/// what makes that call resolve locally instead of hitting Dio — this
/// widget has no auth logic of its own.
///
/// Business Owner and System Admin stay the two primary, always-visible
/// buttons (unchanged from before this pass — this is a development/demo
/// tool, not production UI, and keeping the two most-used entry points
/// prominent matters more here than exposing all nine at once). The other
/// seven business roles (§23) sit behind a "Try another role" toggle,
/// specifically so a reviewer can prove the UI actually changes per role
/// (docs/roles-and-permissions.md §I) without cluttering the default view.
class _DemoModeCard extends StatefulWidget {
  const _DemoModeCard({required this.l10n, required this.isAuthenticating, required this.onContinue});

  final AppLocalizations l10n;
  final bool isAuthenticating;
  final void Function(String phone) onContinue;

  @override
  State<_DemoModeCard> createState() => _DemoModeCardState();
}

class _DemoModeCardState extends State<_DemoModeCard> {
  bool _showMoreRoles = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = widget.l10n;
    final otherRoles = <(String, IconData)>[
      (l10n.demoRoleManager, Icons.manage_accounts_outlined),
      (l10n.demoRoleWarehouseManager, Icons.warehouse_outlined),
      (l10n.demoRoleSalesStaff, Icons.point_of_sale_outlined),
      (l10n.demoRoleInventoryStaff, Icons.inventory_2_outlined),
      (l10n.demoRoleProductionManager, Icons.precision_manufacturing_outlined),
      (l10n.demoRoleAccountant, Icons.receipt_long_outlined),
      (l10n.demoRoleViewer, Icons.visibility_outlined),
    ];
    final otherRolePhones = [
      kDemoManagerPhone,
      kDemoWarehouseManagerPhone,
      kDemoSalesStaffPhone,
      kDemoInventoryStaffPhone,
      kDemoProductionManagerPhone,
      kDemoAccountantPhone,
      kDemoViewerPhone,
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: colors.infoBg, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  l10n.demoModeIndicator,
                  style: AppTypography.statusBadge.copyWith(color: colors.info),
                ),
              ),
            ],
          ),
          Text(l10n.demoModeLoginBanner, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          AppButton(
            label: l10n.continueAsBusinessDemo,
            icon: Icons.storefront_outlined,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: widget.isAuthenticating ? null : () => widget.onContinue(kDemoBusinessPhone),
          ),
          AppButton(
            label: l10n.continueAsSystemAdminDemo,
            icon: Icons.admin_panel_settings_outlined,
            variant: AppButtonVariant.outline,
            expand: true,
            onPressed: widget.isAuthenticating ? null : () => widget.onContinue(kDemoAdminPhone),
          ),
          AppButton(
            label: _showMoreRoles ? l10n.demoRolesToggleHide : l10n.demoRolesToggleShow,
            icon: _showMoreRoles ? Icons.expand_less : Icons.expand_more,
            variant: AppButtonVariant.text,
            expand: true,
            onPressed: () => setState(() => _showMoreRoles = !_showMoreRoles),
          ),
          if (_showMoreRoles)
            for (var i = 0; i < otherRoles.length; i++)
              AppButton(
                label: otherRoles[i].$1,
                icon: otherRoles[i].$2,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                expand: true,
                onPressed: widget.isAuthenticating ? null : () => widget.onContinue(otherRolePhones[i]),
              ),
        ],
      ),
    );
  }
}

class _Branding extends StatelessWidget {
  const _Branding({required this.colors, required this.l10n});
  final AppColors colors;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(14)),
          child: Text('W', style: AppTypography.pageTitle.copyWith(color: colors.onPrimary)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.loginTitle, style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
        Text(l10n.loginSubtitle, style: AppTypography.body.copyWith(color: colors.textMuted)),
      ],
    );
  }
}

enum _BannerTone { error, info }

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.tone});
  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fg, bg) = tone == _BannerTone.error ? (colors.error, colors.errorBg) : (colors.info, colors.infoBg);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(message, style: AppTypography.caption.copyWith(color: fg)),
    );
  }
}
