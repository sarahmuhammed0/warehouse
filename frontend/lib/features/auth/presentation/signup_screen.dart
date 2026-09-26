import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../settings/data/business_type_config.dart';
import '../data/registration_repository.dart';

/// Business self-registration. A business applies for an account and a
/// System Admin decides — §2 keeps the administrator in control of who has
/// an account, so this screen never grants access, it only submits an
/// application.
///
/// Deliberately NOT a login: on success it shows that the application is
/// pending and offers a way back to the sign-in screen. Anything that looked
/// like being signed in would be a lie, since the backend creates the
/// business as `pending` and login refuses it until approved.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final _businessName = TextEditingController();
  // Iraq is the UI default (§14), exactly as on the login screen — the
  // backend never guesses a country code.
  final _businessPhone = TextEditingController(text: '+964');
  final _ownerName = TextEditingController();
  final _ownerPhone = TextEditingController(text: '+964');
  final _password = TextEditingController();

  BusinessType? _businessType;
  bool _submitting = false;
  String? _error;

  /// Set once the backend has accepted the application. The form is replaced
  /// rather than left on screen, so nobody re-submits by reflex.
  String? _acceptedMessage;

  @override
  void dispose() {
    for (final c in [_businessName, _businessPhone, _ownerName, _ownerPhone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final result = await ref.read(registrationRepositoryProvider).register(
        RegistrationDraft(
          businessName: _businessName.text.trim(),
          businessType: businessTypeApiValue(_businessType!),
          businessPhone: _businessPhone.text.trim(),
          ownerName: _ownerName.text.trim(),
          ownerPhone: _ownerPhone.text.trim(),
          password: _password.text,
        ),
      );
      if (!mounted) return;
      setState(() => _acceptedMessage = result.message);
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context)!.errorStateDefaultTitle);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.lg,
              children: [
                _Heading(colors: colors, l10n: l10n),
                if (_acceptedMessage != null)
                  _Accepted(message: _acceptedMessage!, l10n: l10n)
                else
                  AppCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.md,
                        children: [
                          _SectionLabel(text: l10n.signUpBusinessSection),
                          AppTextField(
                            key: const ValueKey('signUpBusinessName'),
                            label: l10n.signUpFieldBusinessName,
                            controller: _businessName,
                            required: true,
                            enabled: !_submitting,
                            validator: required(l10n.requiredFieldMessage),
                          ),
                          AppDropdownField<BusinessType>(
                            key: const ValueKey('signUpBusinessType'),
                            label: l10n.fieldBusinessType,
                            required: true,
                            value: _businessType,
                            options: [
                              for (final type in BusinessType.values)
                                AppSelectOption(type, businessTypeLabel(type)),
                            ],
                            onChanged: _submitting ? null : (v) => setState(() => _businessType = v),
                            validator: (value) => value == null ? l10n.requiredFieldMessage : null,
                          ),
                          AppTextField(
                            key: const ValueKey('signUpBusinessPhone'),
                            label: l10n.fieldPhone,
                            controller: _businessPhone,
                            required: true,
                            keyboardType: TextInputType.phone,
                            enabled: !_submitting,
                            validator: combine([required(l10n.phoneRequired), phone()]),
                          ),
                          _SectionLabel(text: l10n.signUpOwnerSection),
                          AppTextField(
                            key: const ValueKey('signUpOwnerName'),
                            label: l10n.signUpFieldOwnerName,
                            controller: _ownerName,
                            required: true,
                            enabled: !_submitting,
                            validator: required(l10n.requiredFieldMessage),
                          ),
                          AppTextField(
                            key: const ValueKey('signUpOwnerPhone'),
                            label: l10n.phoneNumber,
                            controller: _ownerPhone,
                            required: true,
                            keyboardType: TextInputType.phone,
                            enabled: !_submitting,
                            validator: combine([required(l10n.phoneRequired), phone()]),
                          ),
                          AppTextField.password(
                            key: const ValueKey('signUpPassword'),
                            label: l10n.password,
                            controller: _password,
                            required: true,
                            enabled: !_submitting,
                            helperText: l10n.signUpPasswordHint,
                            // Mirrors the backend's own minimum, so the form
                            // rejects it before a round trip rather than
                            // showing a server error for something local.
                            validator: combine([
                              required(l10n.passwordRequired),
                              minLength(8, l10n.signUpPasswordTooShort),
                            ]),
                          ),
                          if (_error != null) _ErrorBanner(message: _error!),
                          AppButton(
                            key: const ValueKey('signUpSubmitButton'),
                            label: l10n.signUpSubmit,
                            onPressed: _submitting ? null : _submit,
                            loading: _submitting,
                            expand: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                AppButton(
                  key: const ValueKey('signUpBackToLogin'),
                  label: l10n.signUpBackToLogin,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                  onPressed: _submitting ? null : () => context.go(AppRoutes.login),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.colors, required this.l10n});
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
          decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadius.mdRadius),
          child: Text('W', style: AppTypography.pageTitle.copyWith(color: colors.onPrimary)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.signUpTitle, style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
        Text(
          l10n.signUpSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// What the applicant sees once the backend has accepted the application.
/// It states that a decision is pending and nothing more — the response is
/// identical whether or not the phone was already registered (§58), so
/// there is nothing else it could honestly say.
class _Accepted extends StatelessWidget {
  const _Accepted({required this.message, required this.l10n});
  final String message;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      key: const ValueKey('signUpAccepted'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Row(
            spacing: AppSpacing.sm,
            children: [
              Icon(Icons.check_circle_outline, color: colors.success),
              Expanded(
                child: Text(
                  l10n.signUpPendingTitle,
                  style: AppTypography.cardTitle.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          Text(message, style: AppTypography.body.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTypography.label.copyWith(color: context.colors.textSecondary));
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.mdRadius),
      child: Text(message, style: AppTypography.caption.copyWith(color: colors.error)),
    );
  }
}
