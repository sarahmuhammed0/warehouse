import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/forms/selection_controls.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../data/customer_models.dart';
import '../data/customer_providers.dart';

Future<bool?> showCustomerFormDialog(BuildContext context, {Customer? editing}) {
  return showAppDialog<bool>(context, builder: (context) => CustomerFormDialog(editing: editing));
}

class CustomerFormDialog extends ConsumerStatefulWidget {
  const CustomerFormDialog({super.key, this.editing});
  final Customer? editing;

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.editing?.phone ?? '');
  late final _secondaryPhone = TextEditingController(text: widget.editing?.secondaryPhone ?? '');
  late final _email = TextEditingController(text: widget.editing?.email ?? '');
  late final _address = TextEditingController(text: widget.editing?.address ?? '');
  late final _company = TextEditingController(text: widget.editing?.company ?? '');
  late final _notes = TextEditingController(text: widget.editing?.notes ?? '');
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _active = (widget.editing?.status ?? CustomerStatus.active) == CustomerStatus.active;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _secondaryPhone, _email, _address, _company, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = CustomerDraft(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      secondaryPhone: _secondaryPhone.text.trim().isEmpty ? null : _secondaryPhone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      company: _company.text.trim().isEmpty ? null : _company.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      status: _active ? CustomerStatus.active : CustomerStatus.inactive,
    );
    try {
      final repo = ref.read(customerRepositoryProvider);
      if (widget.editing == null) {
        await repo.create(draft);
      } else {
        await repo.update(widget.editing!.id, draft);
      }
      await ref.read(customerListControllerProvider.notifier).reload();
      ref.invalidate(customerPickerOptionsProvider);
      if (widget.editing != null) ref.invalidate(customerByIdProvider(widget.editing!.id));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.unableToSave);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEditing = widget.editing != null;
    return AlertDialog(
      title: Text(isEditing ? '${l10n.edit} — ${widget.editing!.fullName}' : '${l10n.add} ${l10n.navCustomers}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              AppTextField(label: l10n.fieldName, controller: _name, required: true, enabled: !_saving, validator: required(l10n.requiredFieldMessage)),
              AppTextField(label: l10n.fieldPhone, controller: _phone, required: true, enabled: !_saving, keyboardType: TextInputType.phone, validator: required(l10n.requiredFieldMessage)),
              AppTextField(label: l10n.fieldSecondaryPhone, controller: _secondaryPhone, enabled: !_saving, keyboardType: TextInputType.phone),
              AppTextField(label: l10n.fieldEmail, controller: _email, enabled: !_saving, keyboardType: TextInputType.emailAddress),
              AppTextField(label: l10n.fieldCompany, controller: _company, enabled: !_saving),
              AppTextField(label: l10n.fieldAddress, controller: _address, enabled: !_saving),
              AppTextField.multiline(label: l10n.fieldNotes, controller: _notes, enabled: !_saving, maxLines: 2),
              AppSwitch(label: l10n.statusActive, value: _active, onChanged: _saving ? null : (value) => setState(() => _active = value)),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        AppButton(label: isEditing ? l10n.update : l10n.create, loading: _saving, onPressed: _saving ? null : _submit),
      ],
    );
  }
}
