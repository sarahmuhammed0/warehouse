import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
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
  /// Create only — an existing account's password is changed through its own
  /// endpoint, not by reopening the details dialog.
  final _password = TextEditingController();
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
    _password.dispose();
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
      password: widget.editing == null && _password.text.isNotEmpty ? _password.text : null,
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
    } on Failure catch (e) {
      // The server's own words. Every refusal this form can hit says something
      // the person can act on — that a phone number is already taken, that a
      // phone cannot be changed, that the password is too short for this
      // business's policy — and "Unable to save" throws all of that away.
      if (mounted) setState(() => _error = e.message);
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
      // Scrollable, so a form taller than the window scrolls instead of
      // overflowing. Without it a short viewport — a laptop, or a browser
      // pane beside an editor — renders the striped overflow banner across
      // the dialog and clips whatever did not fit, including the buttons.
      scrollable: true,
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
              // The sign-in password, set when the account is made. Create only:
              // changing an existing one is `PUT /users/:id/password`, and
              // offering it here would make a rename look like a reset.
              if (widget.editing == null)
                AppTextField.password(
                  key: const ValueKey('employeePassword'),
                  label: l10n.password,
                  controller: _password,
                  required: true,
                  enabled: !_saving,
                  // Eight is the server's own minimum (`createUserSchema`);
                  // saying so here beats a round trip to be told.
                  validator: combine([required(l10n.requiredFieldMessage), minLength(8, l10n.signUpPasswordTooShort)]),
                ),
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
