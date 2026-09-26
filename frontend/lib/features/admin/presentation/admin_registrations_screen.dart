import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/buttons/app_button.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/feedback/app_error_state.dart';
import '../../../shared/feedback/app_toast.dart';
import '../../../shared/forms/app_text_field.dart';
import '../../../shared/layout/page_scaffold.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../data/registration_queue_repository.dart';

/// §2's account control, as a queue. A business applies for an account and
/// the System Admin decides: approving lets it sign in, rejecting keeps it
/// out and tells it why.
///
/// This is the first admin screen backed by a REAL endpoint rather than demo
/// data — everything else on the admin dashboard still reads
/// `LocalAdminRepository`. In demo mode this screen works too, against
/// `DemoRegistrationQueueRepository`, so it is usable with the backend off.
class AdminRegistrationsScreen extends ConsumerWidget {
  const AdminRegistrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pending = ref.watch(pendingRegistrationsProvider);

    return PageScaffold(
      title: l10n.registrationsTitle,
      subtitle: l10n.registrationsSubtitle,
      // §2's other path to the same outcome: rather than waiting for an
      // application, the administrator creates the business directly.
      primaryAction: AppButton(
        key: const ValueKey('adminCreateBusinessLink'),
        label: l10n.adminCreateBusiness,
        icon: Icons.add,
        onPressed: () => context.go(AppRoutes.adminBusinessCreate),
      ),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorState(
          message: error is Failure ? error.message : l10n.errorStateDefaultDescription,
          onRetry: () => ref.invalidate(pendingRegistrationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              key: const ValueKey('registrationsEmpty'),
              child: Text(
                l10n.registrationsEmpty,
                style: AppTypography.body.copyWith(color: context.colors.textMuted),
              ),
            );
          }
          // A Column, not a ListView: `PageScaffold` already puts its body
          // inside a SingleChildScrollView, so a ListView here has unbounded
          // height and fails layout. The queue is a handful of items awaiting
          // a decision, not a long list, so it does not need its own
          // viewport.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.md,
            children: [
              for (final registration in items) _RegistrationCard(registration: registration),
            ],
          );
        },
      ),
    );
  }
}

class _RegistrationCard extends ConsumerStatefulWidget {
  const _RegistrationCard({required this.registration});
  final BusinessRegistration registration;

  @override
  ConsumerState<_RegistrationCard> createState() => _RegistrationCardState();
}

class _RegistrationCardState extends ConsumerState<_RegistrationCard> {
  bool _busy = false;

  Future<void> _decide(Future<BusinessRegistration> Function() action, String successMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppToast.success(context, successMessage);
      // Refetch rather than mutating a local copy: the decision may have
      // been made by another administrator in the meantime, and the server's
      // answer is the one that counts.
      ref.invalidate(pendingRegistrationsProvider);
    } on Failure catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
      // A 409 means someone else already decided — refresh so the queue
      // stops showing an application that is no longer pending.
      ref.invalidate(pendingRegistrationsProvider);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, AppLocalizations.of(context)!.errorStateDefaultTitle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectReasonDialog(),
    );

    if (reason == null || !mounted) return;
    final repo = ref.read(registrationQueueRepositoryProvider);
    await _decide(() => repo.reject(widget.registration.id, reason), l10n.registrationRejected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final r = widget.registration;

    return AppCard(
      key: ValueKey('registration:${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.sm,
        children: [
          Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: Text(r.name, style: AppTypography.cardTitle.copyWith(color: colors.textPrimary)),
              ),
              StatusBadge(label: r.status, tone: StatusTone.warning),
            ],
          ),
          _Detail(label: l10n.fieldBusinessType, value: r.businessType),
          _Detail(label: l10n.fieldPhone, value: r.phone),
          if (r.ownerName != null)
            _Detail(label: l10n.registrationOwner, value: '${r.ownerName} · ${r.ownerPhone ?? ''}'),
          _Detail(
            label: l10n.registrationSubmittedOn,
            value: '${r.createdAt.year}-${r.createdAt.month.toString().padLeft(2, '0')}-'
                '${r.createdAt.day.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            spacing: AppSpacing.sm,
            children: [
              AppButton(
                key: ValueKey('approve:${r.id}'),
                label: l10n.registrationApprove,
                icon: Icons.check,
                onPressed: _busy
                    ? null
                    : () => _decide(
                        () => ref.read(registrationQueueRepositoryProvider).approve(r.id),
                        l10n.registrationApproved,
                      ),
              ),
              AppButton(
                key: ValueKey('reject:${r.id}'),
                label: l10n.registrationReject,
                icon: Icons.close,
                variant: AppButtonVariant.outline,
                onPressed: _busy ? null : _reject,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A widget rather than an inline `AlertDialog`, for one specific reason:
/// the controller has to outlive the dialog's exit animation. Creating it in
/// the caller and disposing it right after `showDialog` returns throws "A
/// TextEditingController was used after being disposed" — the route is still
/// animating out and its field still reads the controller. Owning it here
/// ties its lifetime to the widget that actually uses it.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      key: const ValueKey('rejectRegistrationDialog'),
      title: Text(l10n.registrationRejectTitle, style: AppTypography.cardTitle),
      // An explicit width, and a field that does not grow: an AlertDialog
      // gives its content unbounded height, and a multi-line field inside
      // one overflows by however much room it thinks it has.
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: AppTextField(
            key: const ValueKey('rejectReasonField'),
            label: l10n.registrationRejectReason,
            controller: _controller,
            required: true,
            helperText: l10n.registrationRejectHint,
            // The backend requires it: a refusal the applicant cannot
            // understand is not much better than silence.
            validator: (value) => (value == null || value.trim().isEmpty) ? l10n.requiredFieldMessage : null,
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          key: const ValueKey('rejectConfirmButton'),
          label: l10n.registrationReject,
          variant: AppButtonVariant.destructive,
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ),
        Expanded(child: Text(value, style: AppTypography.body.copyWith(color: colors.textSecondary))),
      ],
    );
  }
}
