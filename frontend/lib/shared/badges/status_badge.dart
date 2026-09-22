import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The semantic color *group* a status belongs to — separate from any
/// single business status name, so the badge widget itself never needs to
/// know about orders/returns/payments. Kept distinct from the brand accent
/// per the design-system rule that status color and accent color are never
/// the same channel.
enum StatusTone { success, warning, danger, info, neutral }

/// Every status word the specification uses across orders, returns,
/// payments, and production (§14/§16/§22/§24/§34 25). The color/label
/// mapping lives once, here — no future module re-derives "what color is
/// Cancelled" on its own.
enum BusinessStatus {
  active,
  inactive,
  draft,
  pending,
  confirmed,
  processing,
  ready,
  completed,
  cancelled,
  returned,
  partiallyReturned,
  paid,
  partiallyPaid,
  unpaid,
  requested,
  approved,
  rejected,
  planned,
  inProgress,
}

class _StatusConfig {
  const _StatusConfig(this.label, this.tone);
  final String label;
  final StatusTone tone;
}

const Map<BusinessStatus, _StatusConfig> _statusConfig = {
  BusinessStatus.active: _StatusConfig('Active', StatusTone.success),
  BusinessStatus.inactive: _StatusConfig('Inactive', StatusTone.neutral),
  BusinessStatus.draft: _StatusConfig('Draft', StatusTone.neutral),
  BusinessStatus.pending: _StatusConfig('Pending', StatusTone.warning),
  BusinessStatus.confirmed: _StatusConfig('Confirmed', StatusTone.info),
  BusinessStatus.processing: _StatusConfig('Processing', StatusTone.info),
  BusinessStatus.ready: _StatusConfig('Ready', StatusTone.info),
  BusinessStatus.completed: _StatusConfig('Completed', StatusTone.success),
  BusinessStatus.cancelled: _StatusConfig('Cancelled', StatusTone.danger),
  BusinessStatus.returned: _StatusConfig('Returned', StatusTone.warning),
  BusinessStatus.partiallyReturned: _StatusConfig('Partially Returned', StatusTone.warning),
  BusinessStatus.paid: _StatusConfig('Paid', StatusTone.success),
  BusinessStatus.partiallyPaid: _StatusConfig('Partially Paid', StatusTone.warning),
  BusinessStatus.unpaid: _StatusConfig('Unpaid', StatusTone.danger),
  BusinessStatus.requested: _StatusConfig('Requested', StatusTone.neutral),
  BusinessStatus.approved: _StatusConfig('Approved', StatusTone.success),
  BusinessStatus.rejected: _StatusConfig('Rejected', StatusTone.danger),
  BusinessStatus.planned: _StatusConfig('Planned', StatusTone.neutral),
  BusinessStatus.inProgress: _StatusConfig('In Progress', StatusTone.info),
};

/// Resolves a tone to its `(foreground, background)` pair. Shared by the
/// pill and the inline dot so the two can never disagree about what
/// "warning" looks like.
(Color, Color) statusToneColors(BuildContext context, StatusTone tone) {
  final colors = context.colors;
  return switch (tone) {
    StatusTone.success => (colors.success, colors.successBg),
    StatusTone.warning => (colors.warning, colors.warningBg),
    StatusTone.danger => (colors.error, colors.errorBg),
    StatusTone.info => (colors.info, colors.infoBg),
    StatusTone.neutral => (colors.textSecondary, colors.disabledBg),
  };
}

/// Generic status pill. Two ways to use it:
///  - `StatusBadge.forStatus(BusinessStatus.pending)` — the catalog above.
///  - `StatusBadge(label: 'Checking…', tone: StatusTone.neutral)` — for
///    anything not yet in the catalog.
///
/// Never communicates status by color alone (§22 accessibility): the label
/// text is always shown, color is reinforcement, not the only signal. The
/// leading dot is a third channel again — it reads at a glance down a
/// column of rows where the word itself needs a moment.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  factory StatusBadge.forStatus(BusinessStatus status) {
    final config = _statusConfig[status]!;
    return StatusBadge(label: config.label, tone: config.tone);
  }

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = statusToneColors(context, tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillRadius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.statusBadge.copyWith(color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The unenclosed form — a colored dot followed by plain text, for a
/// status inside an already-dense row where a filled pill on every line
/// would be too much ink (§15: "do not make statuses overly bright").
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = statusToneColors(context, tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: AppTypography.tableText.copyWith(color: context.colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A neutral descriptive tag — a business type, a category, a role. Not a
/// status: it carries no state and therefore no semantic color, which is
/// exactly why it must not look like a [StatusBadge].
class AppTag extends StatelessWidget {
  const AppTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
