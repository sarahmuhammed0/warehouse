import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_select_field.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/forms/selection_controls.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../data/category_models.dart';
import '../data/category_providers.dart';

/// Create/edit form (§7) — one dialog for both, matching every other
/// module's form pattern in this app: a dialog for a record that's simple
/// enough not to need its own route (Categories, Customers, Suppliers),
/// versus a full screen for one that isn't (Products, Orders).
Future<bool?> showCategoryFormDialog(BuildContext context, {Category? editing}) {
  return showAppDialog<bool>(
    context,
    builder: (context) => CategoryFormDialog(editing: editing),
  );
}

class CategoryFormDialog extends ConsumerStatefulWidget {
  const CategoryFormDialog({super.key, this.editing});

  final Category? editing;

  @override
  ConsumerState<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.editing?.name ?? '');
  late final _codeController = TextEditingController(text: widget.editing?.code ?? '');
  late final _descriptionController = TextEditingController(text: widget.editing?.description ?? '');
  String? _parentId;
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parentId = widget.editing?.parentId;
    _active = (widget.editing?.status ?? CategoryStatus.active) == CategoryStatus.active;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = CategoryDraft(
      name: _nameController.text.trim(),
      code: _codeController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      parentId: _parentId,
      status: _active ? CategoryStatus.active : CategoryStatus.inactive,
    );
    try {
      final repo = ref.read(categoryRepositoryProvider);
      if (widget.editing == null) {
        await repo.create(draft);
      } else {
        await repo.update(widget.editing!.id, draft);
      }
      await ref.read(categoryListControllerProvider.notifier).reload();
      ref.invalidate(categoryPickerOptionsProvider);
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
    final pickerOptions = ref.watch(categoryPickerOptionsProvider);

    return AlertDialog(
      title: Text(isEditing ? '${l10n.edit} — ${widget.editing!.name}' : '${l10n.add} ${l10n.navCategories}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              AppTextField(
                label: l10n.fieldName,
                controller: _nameController,
                required: true,
                enabled: !_saving,
                validator: required(l10n.requiredFieldMessage),
              ),
              AppTextField(
                label: l10n.fieldCode,
                controller: _codeController,
                required: true,
                enabled: !_saving,
                validator: required(l10n.requiredFieldMessage),
              ),
              pickerOptions.when(
                data: (options) => AppDropdownField<String?>(
                  label: l10n.fieldParentCategory,
                  value: _parentId,
                  options: [
                    AppSelectOption<String?>(null, l10n.noneOption),
                    for (final option in options)
                      if (widget.editing == null || option.id != widget.editing!.id)
                        AppSelectOption<String?>(option.id, option.name),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _parentId = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              AppTextField.multiline(
                label: l10n.fieldDescription,
                controller: _descriptionController,
                enabled: !_saving,
                maxLines: 3,
              ),
              AppSwitch(
                label: l10n.statusActive,
                value: _active,
                onChanged: _saving ? null : (value) => setState(() => _active = value),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: isEditing ? l10n.update : l10n.create,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
