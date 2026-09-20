import 'package:flutter/material.dart' hide required;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/validation/validators.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/overlays/app_dialog.dart';
import '../../../theme/app_typography.dart';
import '../../settings/data/settings_state.dart';
import '../data/admin_business_models.dart';
import '../data/admin_providers.dart';

Future<bool?> showAdminResetPasswordDialog(BuildContext context, {required AdminBusiness business}) {
  return showAppDialog<bool>(context, builder: (context) => AdminResetPasswordDialog(business: business));
}

/// Spec §57's **Reset password** control.
///
/// What it genuinely does, and what it deliberately does not:
///
/// The demo authentication architecture holds no per-account password at
/// all — `DemoAuthRepository.login` ignores the password argument entirely
/// and its `changePassword` is a no-op. So there is no password here for a
/// frontend reset to truthfully change, and the honest options were to
/// leave the control dead (the thing this work exists to fix) or to pop a
/// success toast for an action that changed nothing (worse — a lie in the
/// UI). Neither is acceptable, so this does the third thing: it validates
/// the new password against the app's own configured policy, then records
/// a real, visible piece of local state — `lastPasswordResetAt` on the
/// business, shown back on the detail screen.
///
/// The dialog says plainly, on screen, that no real password changed. When
/// backend work resumes this becomes a call to an admin reset endpoint
/// (spec §38 lists no such route yet — see
/// `docs/frontend-backend-contract-notes.md`) and the notice goes away.
class AdminResetPasswordDialog extends ConsumerStatefulWidget {
  const AdminResetPasswordDialog({super.key, required this.business});

  final AdminBusiness business;

  @override
  ConsumerState<AdminResetPasswordDialog> createState() => _AdminResetPasswordDialogState();
}

class _AdminResetPasswordDialogState extends ConsumerState<AdminResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(adminBusinessListControllerProvider.notifier).resetPassword(widget.business.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The application's own password rule (Settings → Security), so the
    // admin's reset and a business user's own password change can't
    // disagree about what counts as acceptable.
    final minPasswordLength = ref.watch(businessSettingsProvider).minPasswordLength;

    return AlertDialog(
      title: Text('${l10n.adminResetPasswordTitle} — ${widget.business.name}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Text(l10n.adminResetPasswordDescription, style: AppTypography.body),
              AppTextField.password(
                key: const ValueKey('adminNewPassword'),
                label: l10n.fieldNewPassword,
                controller: _password,
                required: true,
                enabled: !_saving,
                validator: combine([
                  required(l10n.passwordRequired),
                  minLength(minPasswordLength, l10n.passwordTooShort(minPasswordLength)),
                ]),
              ),
              AppTextField.password(
                key: const ValueKey('adminConfirmPassword'),
                label: l10n.fieldConfirmPassword,
                controller: _confirm,
                required: true,
                enabled: !_saving,
                validator: (value) {
                  if (value == null || value.isEmpty) return l10n.passwordRequired;
                  if (value != _password.text) return l10n.passwordsDoNotMatch;
                  return null;
                },
              ),
              // Not a footnote: the whole point is that the person clicking
              // this knows exactly what it did.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.adminResetPasswordDemoNotice, style: AppTypography.caption)),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(label: l10n.demoModeIndicator, tone: StatusTone.warning),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        AppButton(
          key: const ValueKey('adminResetPasswordConfirm'),
          label: l10n.adminResetPasswordTitle,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
