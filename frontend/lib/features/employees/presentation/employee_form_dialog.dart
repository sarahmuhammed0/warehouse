import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/forms/selection_controls.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../data/employee_models.dart';
import '../data/employee_providers.dart';

/// §23: "System Admin creates users per business" in the real architecture
/// — this dialog is the business-side equivalent for Phase-3+ (a business
/// Owner adding their own staff accounts), distinct from System Admin's own
/// business-creation flow (`features/admin`).
Future<bool?> showEmployeeFormDialog(BuildContext context, {Employee? editing}) {
  return showAppDialog<bool>(context, builder: (context) => EmployeeFormDialog(editing: editing));
}

class EmployeeFormDialog extends ConsumerStatefulWidget {
  const EmployeeFormDialog({super.key, this.editing});
  final Employee? editing;

  @override
  ConsumerState<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _phone = TextEditingController(text: widget.editing?.phone ?? '');
  late final _email = TextEditingController(text: widget.editing?.email ?? '');
  String? _roleId;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _roleId = widget.editing?.roleId;
    _active = (widget.editing?.status ?? EmployeeStatus.active) == EmployeeStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _roleId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = EmployeeDraft(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      roleId: _roleId!,
      status: _active ? EmployeeStatus.active : EmployeeStatus.inactive,
    );
    try {
      final repo = ref.read(employeeRepositoryProvider);
      if (widget.editing == null) {
        await repo.create(draft);
      } else {
        await repo.update(widget.editing!.id, draft);
      }
      await ref.read(employeeListControllerProvider.notifier).reload();
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
    final rolesAsync = ref.watch(rolesProvider);

    return AlertDialog(
      title: Text(isEditing ? '${l10n.edit} — ${widget.editing!.name}' : '${l10n.add} ${l10n.navEmployees}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              AppTextField(label: l10n.fieldName, controller: _name, required: true, enabled: !_saving, validator: required(l10n.requiredFieldMessage)),
              AppTextField(label: l10n.fieldPhone, controller: _phone, required: true, enabled: !_saving, keyboardType: TextInputType.phone, validator: required(l10n.requiredFieldMessage)),
              AppTextField(label: l10n.fieldEmail, controller: _email, enabled: !_saving, keyboardType: TextInputType.emailAddress),
              rolesAsync.when(
                data: (roles) => AppDropdownField<String>(
                  label: l10n.fieldRole,
                  required: true,
                  value: _roleId,
                  options: [for (final r in roles) AppSelectOption(r.id, r.name)],
                  onChanged: (value) => setState(() => _roleId = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              AppSwitch(label: l10n.statusActive, value: _active, onChanged: _saving ? (_) {} : (value) => setState(() => _active = value)),
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
