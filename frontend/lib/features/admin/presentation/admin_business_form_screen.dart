import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../settings/data/business_type_config.dart';
import '../data/admin_business_models.dart';
import '../data/admin_providers.dart';

/// Spec §57's **Edit** control — the System Admin editing one business's
/// profile.
///
/// A screen rather than a dialog, so the back arrow behaves like every
/// other detail page in the app (`context.pop()` back to the business it
/// was opened from) and so the form has room on a phone.
///
/// Which fields: §57's own "Business profile" block lists Logo, Name, Type,
/// Address, Phone, Email, Status. Status is deliberately absent here — it
/// has its own Disable/Activate control on the detail screen, and two ways
/// to change one value is how they drift apart. Logo is absent because the
/// frontend has no upload pipeline yet (`AdminBusiness.logoUrl` is never
/// populated). §3 lists a wider create-time field set (city, country,
/// website, tax/registration number, currency, language, time zone) that
/// this frontend's business model does not carry — adding empty inputs for
/// fields nothing stores would be a form that lies about what it saves.
class AdminBusinessFormScreen extends ConsumerStatefulWidget {
  const AdminBusinessFormScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<AdminBusinessFormScreen> createState() => _AdminBusinessFormScreenState();
}

class _AdminBusinessFormScreenState extends ConsumerState<AdminBusinessFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  String? _businessType;

  /// The form is prefilled from the loaded business exactly once. Without
  /// this guard a provider refresh mid-edit would overwrite whatever the
  /// admin had typed.
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(AdminBusiness business) {
    if (_prefilled) return;
    _prefilled = true;
    _name.text = business.name;
    _phone.text = business.phone;
    _email.text = business.email ?? '';
    _address.text = business.address ?? '';
    _businessType = business.businessType;
  }

  Future<void> _save(AdminBusiness business) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _name.text.trim();
    try {
      await ref.read(adminBusinessListControllerProvider.notifier).updateBusiness(
            business.id,
            AdminBusinessDraft(
              name: name,
              businessType: _businessType ?? business.businessType,
              phone: _phone.text.trim(),
              email: _email.text.trim().isEmpty ? null : _email.text.trim(),
              address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            ),
          );
      if (!mounted) return;
      AppToast.success(context, AppLocalizations.of(context)!.adminBusinessUpdated(name));
      // Back to the business it was opened from — the real previous page,
      // not a hard-coded route (the fallback only matters on a deep link).
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.adminBusinessDetail(business.id));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, AppLocalizations.of(context)!.unableToSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(adminBusinessByIdProvider(widget.businessId));

    return async.when(
      loading: () => _shell(l10n, const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
      error: (_, _) => _shell(
        l10n,
        AppErrorState(message: l10n.unableToLoad, onRetry: () => ref.invalidate(adminBusinessByIdProvider(widget.businessId))),
      ),
      data: (business) {
        _prefill(business);
        return _shell(
          l10n,
          AppCard(
            title: Text(business.name),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  AppTextField(
                    label: l10n.fieldName,
                    controller: _name,
                    required: true,
                    enabled: !_saving,
                    validator: required(l10n.requiredFieldMessage),
                  ),
                  AppDropdownField<String>(
                    label: l10n.fieldBusinessType,
                    value: _businessType,
                    // §50's seven types, from the same table the sidebar's
                    // module filter reads — never a free-text field, or a
                    // typo here would silently change which modules a
                    // business gets.
                    options: [for (final type in BusinessType.values) AppSelectOption(businessTypeLabel(type), businessTypeLabel(type))],
                    onChanged: _saving ? null : (value) => setState(() => _businessType = value),
                  ),
                  AppTextField(
                    label: l10n.fieldPhone,
                    controller: _phone,
                    required: true,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    validator: required(l10n.requiredFieldMessage),
                  ),
                  AppTextField(label: l10n.fieldEmail, controller: _email, enabled: !_saving, keyboardType: TextInputType.emailAddress),
                  AppTextField(label: l10n.fieldAddress, controller: _address, enabled: !_saving),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton(
                        key: const ValueKey('adminBusinessSave'),
                        label: l10n.save,
                        icon: Icons.check,
                        loading: _saving,
                        onPressed: _saving ? null : () => _save(business),
                      ),
                      AppButton(
                        key: const ValueKey('adminBusinessCancel'),
                        label: l10n.cancel,
                        variant: AppButtonVariant.text,
                        // Cancel changes nothing — it just leaves, same pop
                        // the back arrow does.
                        onPressed: _saving
                            ? null
                            : () => context.canPop() ? context.pop() : context.go(AppRoutes.adminBusinessDetail(business.id)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _shell(AppLocalizations l10n, Widget body) {
    return PageScaffold(
      title: l10n.adminEditBusinessTitle,
      showBackButton: true,
      backFallbackRoute: AppRoutes.adminBusinessDetail(widget.businessId),
      body: body,
    );
  }
}
