import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../auth/data/registration_repository.dart';
import '../../settings/data/business_type_config.dart';
import '../data/registration_queue_repository.dart';

/// §2's "create factory/warehouse/storage-store accounts" — the
/// administrator creating a business directly, rather than waiting for one
/// to apply.
///
/// The business is created **active**: an administrator doing this by hand
/// is the approval, so it never enters the pending queue. That is why this
/// screen and the approvals screen are two different things rather than one
/// with a mode switch.
class AdminBusinessCreateScreen extends ConsumerStatefulWidget {
  const AdminBusinessCreateScreen({super.key});

  @override
  ConsumerState<AdminBusinessCreateScreen> createState() => _AdminBusinessCreateScreenState();
}

class _AdminBusinessCreateScreenState extends ConsumerState<AdminBusinessCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _businessPhone = TextEditingController(text: '+964');
  final _ownerName = TextEditingController();
  final _ownerPhone = TextEditingController(text: '+964');
  final _password = TextEditingController();

  BusinessType? _businessType;
  bool _saving = false;
  String? _error;

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

    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(registrationQueueRepositoryProvider).createBusiness(
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
      AppToast.success(context, l10n.adminBusinessCreated);
      context.go(AppRoutes.adminRegistrations);
    } on Failure catch (e) {
      if (!mounted) return;
      // A duplicate owner phone comes back as a specific 409 here, unlike on
      // the public registration endpoint — this is an authenticated
      // administrator action, so there is no enumeration concern.
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.errorStateDefaultTitle);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return PageScaffold(
      title: l10n.adminCreateBusiness,
      subtitle: l10n.adminCreateBusinessSubtitle,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminRegistrations,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                AppTextField(
                  key: const ValueKey('adminCreateBusinessName'),
                  label: l10n.signUpFieldBusinessName,
                  controller: _businessName,
                  required: true,
                  enabled: !_saving,
                  validator: required(l10n.requiredFieldMessage),
                ),
                AppDropdownField<BusinessType>(
                  key: const ValueKey('adminCreateBusinessType'),
                  label: l10n.fieldBusinessType,
                  required: true,
                  value: _businessType,
                  options: [
                    for (final type in BusinessType.values) AppSelectOption(type, businessTypeLabel(type)),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _businessType = v),
                  validator: (value) => value == null ? l10n.requiredFieldMessage : null,
                ),
                AppTextField(
                  key: const ValueKey('adminCreateBusinessPhone'),
                  label: l10n.fieldPhone,
                  controller: _businessPhone,
                  required: true,
                  keyboardType: TextInputType.phone,
                  enabled: !_saving,
                  validator: combine([required(l10n.phoneRequired), phone()]),
                ),
                AppTextField(
                  key: const ValueKey('adminCreateOwnerName'),
                  label: l10n.signUpFieldOwnerName,
                  controller: _ownerName,
                  required: true,
                  enabled: !_saving,
                  validator: required(l10n.requiredFieldMessage),
                ),
                AppTextField(
                  key: const ValueKey('adminCreateOwnerPhone'),
                  label: l10n.phoneNumber,
                  controller: _ownerPhone,
                  required: true,
                  keyboardType: TextInputType.phone,
                  enabled: !_saving,
                  validator: combine([required(l10n.phoneRequired), phone()]),
                ),
                AppTextField.password(
                  key: const ValueKey('adminCreateOwnerPassword'),
                  label: l10n.password,
                  controller: _password,
                  required: true,
                  enabled: !_saving,
                  helperText: l10n.signUpPasswordHint,
                  validator: combine([
                    required(l10n.passwordRequired),
                    minLength(8, l10n.signUpPasswordTooShort),
                  ]),
                ),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.mdRadius),
                    child: Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
                  ),
                AppButton(
                  key: const ValueKey('adminCreateBusinessSubmit'),
                  label: l10n.adminCreateBusiness,
                  onPressed: _saving ? null : _submit,
                  loading: _saving,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
